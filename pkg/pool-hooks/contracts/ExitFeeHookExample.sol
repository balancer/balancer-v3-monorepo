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
    TokenConfig
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { BaseHooks } from "@balancer-labs/v3-vault/contracts/BaseHooks.sol";

contract ExitFeeHookExample is BaseHooks, Ownable {
    using FixedPoint for uint256;

    // Percentages are represented as 18-decimal FP, with maximum value of 1e18 (100%), so 60 bits are enough.
    uint64 public removeLiquidityHookFeePercentage;

    // Max fee of 10%
    uint64 public constant MAX_EXIT_HOOK_FEE = 1e17;

    /// @dev Exit hook fee above limit.
    error ExitHookFeeAboveLimit(uint256 fee, uint256 limit);

    /// @dev Pool does not support adding liquidity through donation.
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
    ) external view override onlyVault returns (bool) {
        // NOTICE: In real hooks, make sure this function is properly implemented (e.g. check the factory, and check
        // that the given pool is from the factory). Returning true allows any pool, with any configuration, to use
        // this hook

        // This hook requires donation support to work
        if (liquidityManagement.enableDonation == false) {
            revert PoolDoesNotSupportDonation();
        }

        return true;
    }

    /// @inheritdoc IHooks
    function getHookFlags() external pure override returns (HookFlags memory) {
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
    ) external override onlyVault returns (bool, uint256[] memory hookAdjustedAmountsOutRaw) {
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

        if (removeLiquidityHookFeePercentage > 0) {
            // Charge fees proportional to amounts out of each token
            for (uint256 i = 0; i < amountsOutRaw.length; i++) {
                uint256 hookFee = amountsOutRaw[i].mulDown(removeLiquidityHookFeePercentage);
                accruedFees[i] = hookFee;
                hookAdjustedAmountsOutRaw[i] -= hookFee;
                // Fees don't need to be transferred to the hook, because donation will reinsert them in the vault
            }

            // Donates accrued fees back to LPs
            _vault.addLiquidity(
                AddLiquidityParams({
                    pool: pool,
                    to: msg.sender, // It would mint BPTs to router, but it's a donation so no BPT is minted
                    maxAmountsIn: accruedFees, // Donate all accrued fees back to the pool (i.e. to the LPs)
                    minBptAmountOut: 0, // Donation does not return BPTs, any number above 0 will revert
                    kind: AddLiquidityKind.DONATION,
                    userData: bytes("") // User data is not used by donation, so we can set to an empty string
                })
            );
        }

        return (true, hookAdjustedAmountsOutRaw);
    }

    // Setters
    // Sets the hook remove liquidity fee percentage, which will be accrued after a remove liquidity operation was
    // executed. This function must be permissioned.
    function setRemoveLiquidityHookFeePercentage(uint64 hookFeePercentage) public onlyOwner {
        if (hookFeePercentage > MAX_EXIT_HOOK_FEE) {
            revert ExitHookFeeAboveLimit(hookFeePercentage, MAX_EXIT_HOOK_FEE);
        }
        removeLiquidityHookFeePercentage = hookFeePercentage;
    }
}
