// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import {
    AddLiquidityKind,
    LiquidityManagement,
    RemoveLiquidityKind,
    SwapKind,
    TokenConfig
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { BasePoolHooks } from "@balancer-labs/v3-vault/contracts/BasePoolHooks.sol";

contract FeeTakingHook is BasePoolHooks {
    using FixedPoint for uint256;

    uint256 public hookSwapFeePercentage;
    uint256 public addLiquidityHookFeePercentage;
    uint256 public removeLiquidityHookFeePercentage;

    constructor(IVault vault) BasePoolHooks(vault) {}

    /// @inheritdoc IHooks
    function onRegister(
        address,
        address,
        TokenConfig[] memory,
        LiquidityManagement calldata
    ) external view override onlyVault returns (bool) {
        // NOTICE: In real hooks, make sure this function is properly implemented. Returning true allows any pool, with
        // any configuration, to use this hook
        return true;
    }

    /// @inheritdoc IHooks
    function getHookFlags() external pure override returns (HookFlags memory) {
        HookFlags memory hookFlags;
        hookFlags.shouldCallAfterSwap = true;
        hookFlags.shouldCallAfterAddLiquidity = true;
        hookFlags.shouldCallAfterRemoveLiquidity = true;
        return hookFlags;
    }

    /// @inheritdoc IHooks
    function onAfterSwap(
        AfterSwapParams calldata params
    ) external override onlyVault returns (bool success, uint256 hookAdjustedAmountCalculatedRaw) {
        hookAdjustedAmountCalculatedRaw = params.amountCalculatedRaw;
        if (hookSwapFeePercentage > 0) {
            uint256 hookFee = hookAdjustedAmountCalculatedRaw.mulDown(hookSwapFeePercentage);
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
    ) external override returns (bool success, uint256[] memory) {
        // Our current architecture only supports fees on tokens. Since we must always respect exact `amountsIn`, and
        // non-proportional add liquidity operations would require taking fees in BPT, we only support proportional
        // addLiquidity.
        if (kind != AddLiquidityKind.PROPORTIONAL) {
            // Make the transaction revert by returning false. The second argument does not matter
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
    ) external override returns (bool, uint256[] memory hookAdjustedAmountsOutRaw) {
        // Currently, the hook fee implementation for onAfterRemoveLiquidity only support proportional removeLiquidity.
        // That's because other types of removeLiquidity requires an exact amount out, so fees need to be charged as
        // BPTs, and our current architecture does not support it.
        if (kind != RemoveLiquidityKind.PROPORTIONAL) {
            // Make the transaction revert by returning false. The second argument does not matter
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

    // Setters

    // Sets the hook swap fee percentage, which will be accrued after a swap was executed
    function setHookSwapFeePercentage(uint256 feePercentage) external {
        hookSwapFeePercentage = feePercentage;
    }

    // Sets the hook add liquidity fee percentage, which will be accrued after an add liquidity operation was executed
    function setAddLiquidityHookFeePercentage(uint256 hookFeePercentage) public {
        addLiquidityHookFeePercentage = hookFeePercentage;
    }

    // Sets the hook remove liquidity fee percentage, which will be accrued after a remove liquidity operation was
    // executed
    function setRemoveLiquidityHookFeePercentage(uint256 hookFeePercentage) public {
        removeLiquidityHookFeePercentage = hookFeePercentage;
    }
}
