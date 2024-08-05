// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import {
    AddLiquidityKind,
    AddLiquidityParams,
    LiquidityManagement,
    RemoveLiquidityKind,
    TokenConfig,
    HookFlags
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { BaseHooks } from "@balancer-labs/v3-vault/contracts/BaseHooks.sol";

/**
 * @notice Impose an "exit fee" on a pool. The value of the fee is returned to the LPs.
 * @dev This hook extracts a fee on all withdrawals, then donates it back to the pool (effectively increasing the value
 * of BPT shares for all users).
 *
 * Since the Vault always takes fees on the calculated amounts, and only supports taking fees in tokens, this hook
 * must be restricted to pools that require proportional liquidity operations. The calculated amount for EXACT_OUT
 * withdrawals would be in BPT, and charging fees on BPT is unsupported.
 *
 * Since the fee must be taken *after* the `amountOut` is calculated - and the actual `amountOut` returned to the Vault
 * must be modified in order to charge the fee - `enableHookAdjustedAmounts` must also be set to true in the
 * pool configuration. Otherwise, the Vault would ignore the adjusted values, and not recognize the fee.
 *
 * Finally, since the only way to deposit fee tokens back into the pool balance (without minting new BPT) is through
 * the special "donation" add liquidity type, this hook also requires that the pool support donation.
 */
contract ExitFeeHookExample is BaseHooks, Ownable {
    using FixedPoint for uint256;

    // Percentages are represented as 18-decimal FP numbers, which have a maximum value of FixedPoint.ONE (100%),
    // so 60 bits are sufficient.
    uint64 public exitFeePercentage;

    // Maximum exit fee of 10%
    uint64 public constant MAX_EXIT_FEE_PERCENTAGE = 10e16;

    /**
     * @dev The exit fee cannot exceed the maximum allowed percentage.
     * @param feePercentage The fee percentage exceeding the limit
     * @param limit The maximum exit fee percentage
     */
    error ExitFeeAboveLimit(uint256 feePercentage, uint256 limit);

    /**
     * @dev The pool does not support adding liquidity through donation.
     * There is an existing similar error (IVaultErrors.DoesNotSupportDonation), but hooks should not throw
     * "Vault" errors.
     */
    error PoolDoesNotSupportDonation();

    constructor(IVault vault) BaseHooks(vault) Ownable(msg.sender) {
        // solhint-disable-previous-line no-empty-blocks
    }

    /// @inheritdoc IHooks
    function onRegister(
        address,
        address,
        TokenConfig[] memory,
        LiquidityManagement calldata liquidityManagement
    ) public view override onlyVault returns (bool) {
        // NOTICE: In real hooks, make sure this function is properly implemented (e.g. check the factory, and check
        // that the given pool is from the factory). Returning true unconditionally allows any pool, with any
        // configuration, to use this hook.

        // This hook requires donation support to work (see above).
        if (liquidityManagement.enableDonation == false) {
            revert PoolDoesNotSupportDonation();
        }

        return true;
    }

    /// @inheritdoc IHooks
    function getHookFlags() public pure override returns (HookFlags memory) {
        HookFlags memory hookFlags;
        // `enableHookAdjustedAmounts` must be true for all contracts that modify the `amountCalculated`
        // in after hooks. Otherwise, the Vault will ignore any "hookAdjusted" amounts, and the transaction
        // might not settle. (It should be false if the after hooks do something else.)
        hookFlags.enableHookAdjustedAmounts = true;
        hookFlags.shouldCallAfterRemoveLiquidity = true;
        return hookFlags;
    }

    /// @inheritdoc IHooks
    function onAfterRemoveLiquidity(
        address,
        address pool,
        RemoveLiquidityKind kind,
        uint256,
        uint256[] memory,
        uint256[] memory amountsOutRaw,
        uint256[] memory,
        bytes memory
    ) public override onlyVault returns (bool, uint256[] memory hookAdjustedAmountsOutRaw) {
        // Our current architecture only supports fees on tokens. Since we must always respect exact `amountsOut`, and
        // non-proportional remove liquidity operations would require taking fees in BPT, we only support proportional
        // removeLiquidity.
        if (kind != RemoveLiquidityKind.PROPORTIONAL) {
            // Returning false will make the transaction revert, so the second argument does not matter.
            return (false, amountsOutRaw);
        }

        IERC20[] memory tokens = _vault.getPoolTokens(pool);
        uint256[] memory accruedFees = new uint256[](tokens.length);
        hookAdjustedAmountsOutRaw = amountsOutRaw;

        if (exitFeePercentage > 0) {
            // Charge fees proportional to the `amountOut` of each token.
            for (uint256 i = 0; i < amountsOutRaw.length; i++) {
                uint256 exitFee = amountsOutRaw[i].mulDown(exitFeePercentage);
                accruedFees[i] = exitFee;
                hookAdjustedAmountsOutRaw[i] -= exitFee;
                // Fees don't need to be transferred to the hook, because donation will redeposit them in the vault.
                // In effect, we will transfer a reduced amount of tokensOut to the caller, and leave the remainder
                // in the pool balance.
            }

            // Donates accrued fees back to LPs
            _vault.addLiquidity(
                AddLiquidityParams({
                    pool: pool,
                    to: msg.sender, // It would mint BPTs to router, but it's a donation so no BPT is minted
                    maxAmountsIn: accruedFees, // Donate all accrued fees back to the pool (i.e. to the LPs)
                    minBptAmountOut: 0, // Donation does not return BPTs, any number above 0 will revert
                    kind: AddLiquidityKind.DONATION,
                    userData: bytes("") // User data is not used by donation, so we can set it to an empty string
                })
            );
        }

        return (true, hookAdjustedAmountsOutRaw);
    }

    // Permissioned functions

    /**
     * @notice Sets the hook remove liquidity fee percentage, charged on every remove liquidity operation.
     * @dev This function must be permissioned.
     */
    function setExitFeePercentage(uint64 newExitFeePercentage) external onlyOwner {
        if (newExitFeePercentage > MAX_EXIT_FEE_PERCENTAGE) {
            revert ExitFeeAboveLimit(newExitFeePercentage, MAX_EXIT_FEE_PERCENTAGE);
        }
        exitFeePercentage = newExitFeePercentage;
    }
}
