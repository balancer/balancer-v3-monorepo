// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import {
    LiquidityManagement,
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
    ) external override onlyVault returns (bool) {
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
                // In EXACT_IN, the amount calculated is the amount of tokens out. The hook needs to charge the fee
                // from amount calculated, so we will take an amount from the total tokens out, and update the amount
                // calculated accordingly
                hookAdjustedAmountCalculatedRaw -= hookFee;
                // Vault sends tokens to hook and registers the debt. Since amounts calculated is the amount out of
                // the swap operation, a credit was already supplied to the current operation, so this hookFee debt
                // will be discounted from there
                _vault.sendTo(params.tokenOut, address(this), hookFee);
            } else {
                // In EXACT_OUT, the amount calculated is the amount of tokens in. The hook needs to charge the fee
                // from amount calculated, so we will increase the amount of tokens in that the user needs to pay.
                hookAdjustedAmountCalculatedRaw += hookFee;
                // Vault sends tokens to hook and registers the debt. Since amounts calculated is the amount in of
                // the swap operation, this debt will increase the amount of tokens in that needs to be settled by the
                // router
                _vault.sendTo(params.tokenIn, address(this), hookFee);
            }
        }
        return (true, hookAdjustedAmountCalculatedRaw);
    }

    // Setters

    // Sets the hook swap fee percentage, which will be accrued after a swap was executed
    function setHookSwapFeePercentage(uint256 feePercentage) external {
        hookSwapFeePercentage = feePercentage;
    }
}
