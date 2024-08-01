// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import {
    AddLiquidityKind,
    LiquidityManagement,
    RemoveLiquidityKind,
    AfterSwapParams,
    SwapKind,
    TokenConfig,
    HookFlags
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { BaseHooks } from "@balancer-labs/v3-vault/contracts/BaseHooks.sol";

/**
 * @notice A hook that takes a fee on all operations.
 * @dev This hook extracts fees on all operations (swaps, add and remove liquidity), retaining them in the hook.
 *
 * Since the Vault always takes fees on the calculated amounts, and only supports taking fees in tokens, this hook
 * must be restricted to pools that require proportional liquidity operations. For example, the calculated amount
 * for EXACT_OUT withdrawals would be in BPT, and charging fees on BPT is unsupported.
 *
 * Since the fee must be taken *after* the `amountOut` is calculated - and the actual `amountOut` returned to the Vault
 * must be modified in order to charge the fee - `enableHookAdjustedAmounts` must also be set to true in the
 * pool configuration. Otherwise, the Vault would ignore the adjusted values, and not recognize the fee.
 */
contract FeeTakingHookExample is BaseHooks, Ownable {
    using FixedPoint for uint256;
    using SafeERC20 for IERC20;

    // Percentages are represented as 18-decimal FP numbers, which have a maximum value of FixedPoint.ONE (100%),
    // so 60 bits are sufficient.
    uint64 public hookSwapFeePercentage;
    uint64 public addLiquidityHookFeePercentage;
    uint64 public removeLiquidityHookFeePercentage;

    constructor(IVault vault) BaseHooks(vault) Ownable(msg.sender) {
        // solhint-disable-previous-line no-empty-blocks
    }

    /// @inheritdoc IHooks
    function onRegister(
        address,
        address,
        TokenConfig[] memory,
        LiquidityManagement calldata
    ) public view override onlyVault returns (bool) {
        // NOTICE: In real hooks, make sure this function is properly implemented (e.g. check the factory, and check
        // that the given pool is from the factory). Returning true unconditionally allows any pool, with any
        // configuration, to use this hook.

        return true;
    }

    /// @inheritdoc IHooks
    function getHookFlags() public pure override returns (HookFlags memory) {
        HookFlags memory hookFlags;
        // `enableHookAdjustedAmounts` must be true for all contracts that modify the `amountCalculated`
        // in after hooks. Otherwise, the Vault will ignore any "hookAdjusted" amounts, and the transaction
        // might not settle. (It should be false if the after hooks do something else.)
        hookFlags.enableHookAdjustedAmounts = true;
        hookFlags.shouldCallAfterSwap = true;
        hookFlags.shouldCallAfterAddLiquidity = true;
        hookFlags.shouldCallAfterRemoveLiquidity = true;
        return hookFlags;
    }

    /// @inheritdoc IHooks
    function onAfterSwap(
        AfterSwapParams calldata params
    ) public override onlyVault returns (bool success, uint256 hookAdjustedAmountCalculatedRaw) {
        hookAdjustedAmountCalculatedRaw = params.amountCalculatedRaw;
        if (hookSwapFeePercentage > 0) {
            uint256 hookFee = params.amountCalculatedRaw.mulDown(hookSwapFeePercentage);
            if (params.kind == SwapKind.EXACT_IN) {
                // For EXACT_IN swaps, the `amountCalculated` is the amount of `tokenOut`. The fee must be taken
                // from `amountCalculated`, so we decrease the amount of tokens the Vault will send to the caller.
                //
                // The preceding swap operation has already credited the original `amountCalculated`. Since we're
                // returning `amountCalculated - hookFee` here, it will only register debt for that reduced amount
                // on settlement. This call to `sendTo` pulls `hookFee` tokens of `tokenOut` from the Vault to this
                // contract, and registers the additional debt, so that the total debts match the credits and
                // settlement succeeds.
                hookAdjustedAmountCalculatedRaw -= hookFee;
                _vault.sendTo(params.tokenOut, address(this), hookFee);
            } else {
                // For EXACT_OUT swaps, the `amountCalculated` is the amount of `tokenIn`. The fee must be taken
                // from `amountCalculated`, so we increase the amount of tokens the Vault will ask from the user.
                //
                // The preceding swap operation has already registered debt for the original `amountCalculated`.
                // Since we're returning `amountCalculated + hookFee` here, it will supply credit for that increased
                // amount on settlement. This call to `sendTo` pulls `hookFee` tokens of `tokenIn` from the Vault to
                // this contract, and registers the additional debt, so that the total debts match the credits and
                // settlement succeeds.
                hookAdjustedAmountCalculatedRaw += hookFee;
                _vault.sendTo(params.tokenIn, address(this), hookFee);
            }
        }
        return (true, hookAdjustedAmountCalculatedRaw);
    }

    /// @inheritdoc IHooks
    function onAfterAddLiquidity(
        address,
        address pool,
        AddLiquidityKind kind,
        uint256[] memory,
        uint256[] memory amountsInRaw,
        uint256,
        uint256[] memory,
        bytes memory
    ) public override onlyVault returns (bool success, uint256[] memory) {
        // Our current architecture only supports fees on tokens. Since we must always respect exact `amountsIn`, and
        // non-proportional add liquidity operations would require taking fees in BPT, we only support proportional
        // addLiquidity.
        if (kind != AddLiquidityKind.PROPORTIONAL) {
            // Returning false will make the transaction revert, so the second argument does not matter.
            return (false, amountsInRaw);
        }

        IERC20[] memory tokens = _vault.getPoolTokens(pool);
        uint256[] memory hookAdjustedAmountsInRaw = amountsInRaw;

        if (addLiquidityHookFeePercentage > 0) {
            // Charge fees proportional to amounts in of each token
            for (uint256 i = 0; i < amountsInRaw.length; i++) {
                uint256 hookFee = amountsInRaw[i].mulDown(addLiquidityHookFeePercentage);
                hookAdjustedAmountsInRaw[i] += hookFee;
                // Sends the hook fee to the hook and registers the debt in the vault
                _vault.sendTo(tokens[i], address(this), hookFee);
            }
        }

        return (true, hookAdjustedAmountsInRaw);
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
        hookAdjustedAmountsOutRaw = amountsOutRaw;

        if (removeLiquidityHookFeePercentage > 0) {
            // Charge fees proportional to amounts out of each token
            for (uint256 i = 0; i < amountsOutRaw.length; i++) {
                uint256 hookFee = amountsOutRaw[i].mulDown(removeLiquidityHookFeePercentage);
                hookAdjustedAmountsOutRaw[i] -= hookFee;
                // Sends the hook fee to the hook and registers the debt in the vault
                _vault.sendTo(tokens[i], address(this), hookFee);
            }
        }

        return (true, hookAdjustedAmountsOutRaw);
    }

    // Permissioned functions

    /**
     * @notice Sets the hook swap fee percentage, charged on every swap operation.
     * @dev This function must be permissioned.
     */
    function setHookSwapFeePercentage(uint64 feePercentage) external onlyOwner {
        hookSwapFeePercentage = feePercentage;
    }

    /**
     * @notice Sets the hook add liquidity fee percentage, charged on every add liquidity operation.
     * @dev This function must be permissioned.
     */
    function setAddLiquidityHookFeePercentage(uint64 hookFeePercentage) external onlyOwner {
        addLiquidityHookFeePercentage = hookFeePercentage;
    }

    /**
     * @notice Sets the hook remove liquidity fee percentage, charged on every remove liquidity operation.
     * @dev This function must be permissioned.
     */
    function setRemoveLiquidityHookFeePercentage(uint64 hookFeePercentage) external onlyOwner {
        removeLiquidityHookFeePercentage = hookFeePercentage;
    }

    /// @notice Withdraws the accumulated fees and sends them to the owner.
    function withdrawFees(IERC20 feeToken) external {
        feeToken.safeTransfer(owner(), feeToken.balanceOf(address(this)));
    }
}
