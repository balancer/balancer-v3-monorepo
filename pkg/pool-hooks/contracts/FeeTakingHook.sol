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
        // Currently, the hook fee implementation for onAfterAddLiquidity only support proportional addLiquidity.
        // That's because other types of addLiquidity requires an exact amount in, so fees need to be charged as BPTs,
        // and our current architecture does not support it.
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
