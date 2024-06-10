// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { WordCodec } from "@balancer-labs/v3-solidity-utils/contracts/helpers/WordCodec.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

library HooksConfigLib {
    /**
     * @dev Check if dynamic swap fee hook should be called and call it. Throws an error if the hook contract fails to
     * execute the hook.
     *
     * @param config The encoded hooks configuration
     * @param swapParams The swap parameters used to calculate the fee
     * @return success false if hook is disabled, true if hooks is enabled and succeeded to execute
     * @return swapFeePercentage the calculated swap fee percentage. 0 if hook is disabled
     */
    function onComputeDynamicSwapFee(
        HooksConfig memory config,
        IBasePool.PoolSwapParams memory swapParams
    ) internal view returns (bool, uint256) {
        if (config.shouldCallComputeDynamicSwapFee == false) {
            return (false, 0);
        }

        (bool success, uint256 swapFeePercentage) = IHooks(config.hooksContract).onComputeDynamicSwapFee(swapParams);

        if (success == false) {
            revert IVaultErrors.DynamicSwapFeeHookFailed();
        }
        return (success, swapFeePercentage);
    }

    /**
     * @dev Check if before swap hook should be called and call it. Throws an error if the hook contract fails to
     * execute the hook.
     *
     * @param config The encoded hooks configuration
     * @param swapParams The swap parameters used in the hook
     * @param pool Pool address
     * @return success false if hook is disabled, true if hooks is enabled and succeeded to execute
     */
    function onBeforeSwap(
        HooksConfig memory config,
        IBasePool.PoolSwapParams memory swapParams,
        address pool
    ) internal returns (bool) {
        if (config.shouldCallBeforeSwap == false) {
            // Hook contract does not implement onBeforeSwap, so success is false (hook was not executed)
            return false;
        }

        if (IHooks(config.hooksContract).onBeforeSwap(swapParams, pool) == false) {
            // Hook contract implements onBeforeSwap, but it has failed, so reverts the transaction.
            revert IVaultErrors.BeforeSwapHookFailed();
        }
        return true;
    }

    /**
     * @dev Check if after swap hook should be called and call it. Throws an error if the hook contract fails to
     * execute the hook.
     *
     * @param config The encoded hooks configuration
     * @param amountCalculatedScaled18 Token amount calculated by the swap
     * @param amountCalculatedRaw Token amount calculated by the swap
     * @param params The swap parameters
     * @param state Temporary state used in swap operations
     * @param poolData Struct containing balance and token information of the pool
     * @return success false if hook is disabled, true if hooks is enabled and succeeded to execute
     * @return hookAdjustedAmountCalculatedRaw New amount calculated, modified by the hook
     */
    function onAfterSwap(
        HooksConfig memory config,
        uint256 amountCalculatedScaled18,
        uint256 amountCalculatedRaw,
        address router,
        SwapParams memory params,
        SwapState memory state,
        PoolData memory poolData
    ) internal returns (bool success, uint256 hookAdjustedAmountCalculatedRaw) {
        if (config.shouldCallAfterSwap == false) {
            // Hook contract does not implement onAfterSwap, so success is false (hook was not executed) and do not
            // change amountCalculatedRaw (no deltas)
            return (false, amountCalculatedRaw);
        }

        // Adjust balances for the AfterSwap hook.
        (uint256 amountInScaled18, uint256 amountOutScaled18) = params.kind == SwapKind.EXACT_IN
            ? (state.amountGivenScaled18, amountCalculatedScaled18)
            : (amountCalculatedScaled18, state.amountGivenScaled18);

        (success, hookAdjustedAmountCalculatedRaw) = IHooks(config.hooksContract).onAfterSwap(
            IHooks.AfterSwapParams({
                kind: params.kind,
                tokenIn: params.tokenIn,
                tokenOut: params.tokenOut,
                amountInScaled18: amountInScaled18,
                amountOutScaled18: amountOutScaled18,
                tokenInBalanceScaled18: poolData.balancesLiveScaled18[state.indexIn],
                tokenOutBalanceScaled18: poolData.balancesLiveScaled18[state.indexOut],
                amountCalculatedScaled18: amountCalculatedScaled18,
                amountCalculatedRaw: amountCalculatedRaw,
                router: router,
                pool: params.pool,
                userData: params.userData
            })
        );

        if (success == false) {
            // Hook contract implements onAfterSwap, but it has failed, so reverts the transaction.
            revert IVaultErrors.AfterSwapHookFailed();
        }

        if (
            (params.kind == SwapKind.EXACT_IN && hookAdjustedAmountCalculatedRaw < params.limitRaw) ||
            (params.kind == SwapKind.EXACT_OUT && hookAdjustedAmountCalculatedRaw > params.limitRaw)
        ) {
            revert IVaultErrors.SwapLimit(hookAdjustedAmountCalculatedRaw, params.limitRaw);
        }
    }

    /**
     * @dev Check if before add liquidity hook should be called and call it. Throws an error if the hook contract fails
     * to execute the hook.
     *
     * @param config The encoded hooks configuration
     * @param maxAmountsInScaled18 An array with maximum amounts for each input token of the add liquidity operation
     * @param params The add liquidity parameters
     * @param poolData Struct containing balance and token information of the pool
     * @return success false if hook is disabled, true if hooks is enabled and succeeded to execute
     */
    function onBeforeAddLiquidity(
        HooksConfig memory config,
        uint256[] memory maxAmountsInScaled18,
        address router,
        AddLiquidityParams memory params,
        PoolData memory poolData
    ) internal returns (bool) {
        if (config.shouldCallBeforeAddLiquidity == false) {
            return false;
        }

        if (
            IHooks(config.hooksContract).onBeforeAddLiquidity(
                router,
                params.kind,
                maxAmountsInScaled18,
                params.minBptAmountOut,
                poolData.balancesLiveScaled18,
                params.userData
            ) == false
        ) {
            revert IVaultErrors.BeforeAddLiquidityHookFailed();
        }
        return true;
    }

    /**
     * @dev Check if after add liquidity hook should be called and call it. Throws an error if the hook contract fails
     * to execute the hook.
     *
     * @param config The encoded hooks configuration
     * @param amountsInScaled18 Scaled amounts of tokens added in token registration order
     * @param bptAmountOut The BPT amount a user will receive after add liquidity operation succeeds
     * @param params The add liquidity parameters
     * @param poolData Struct containing balance and token information of the pool
     */
    function onAfterAddLiquidity(
        HooksConfig memory config,
        uint256[] memory amountsInScaled18,
        uint256 bptAmountOut,
        address router,
        AddLiquidityParams memory params,
        PoolData memory poolData
    ) internal {
        if (config.shouldCallAfterAddLiquidity == false) {
            return;
        }

        if (
            IHooks(config.hooksContract).onAfterAddLiquidity(
                router,
                amountsInScaled18,
                bptAmountOut,
                poolData.balancesLiveScaled18,
                params.userData
            ) == false
        ) {
            revert IVaultErrors.AfterAddLiquidityHookFailed();
        }
    }

    /**
     * @dev Check if before remove liquidity hook should be called and call it. Throws an error if the hook contract
     * fails to execute the hook.
     *
     * @param config The encoded hooks configuration
     * @param minAmountsOutScaled18 An array with minimum amounts for each output token of the remove liquidity
     * operation
     * @param params The remove liquidity parameters
     * @param poolData Struct containing balance and token information of the pool
     * @return success false if hook is disabled, true if hooks is enabled and succeeded to execute
     */
    function onBeforeRemoveLiquidity(
        HooksConfig memory config,
        uint256[] memory minAmountsOutScaled18,
        address router,
        RemoveLiquidityParams memory params,
        PoolData memory poolData
    ) internal returns (bool) {
        if (config.shouldCallBeforeRemoveLiquidity == false) {
            return false;
        }

        if (
            IHooks(config.hooksContract).onBeforeRemoveLiquidity(
                router,
                params.kind,
                params.maxBptAmountIn,
                minAmountsOutScaled18,
                poolData.balancesLiveScaled18,
                params.userData
            ) == false
        ) {
            revert IVaultErrors.BeforeRemoveLiquidityHookFailed();
        }
        return true;
    }

    /**
     * @dev Check if after remove liquidity hook should be called and call it. Throws an error if the hook contract
     * fails to execute the hook.
     *
     * @param config The encoded hooks configuration
     * @param amountsOutScaled18 Amount of tokens to receive in token registration order
     * @param bptAmountIn The BPT amount a user will need burn to remove the liquidity of the pool
     * @param params The remove liquidity parameters
     * @param poolData Struct containing balance and token information of the pool
     */
    function onAfterRemoveLiquidity(
        HooksConfig memory config,
        uint256[] memory amountsOutScaled18,
        uint256 bptAmountIn,
        address router,
        RemoveLiquidityParams memory params,
        PoolData memory poolData
    ) internal {
        if (config.shouldCallAfterRemoveLiquidity == false) {
            return;
        }

        if (
            IHooks(config.hooksContract).onAfterRemoveLiquidity(
                router,
                bptAmountIn,
                amountsOutScaled18,
                poolData.balancesLiveScaled18,
                params.userData
            ) == false
        ) {
            revert IVaultErrors.AfterRemoveLiquidityHookFailed();
        }
    }

    /**
     * @dev Check if before initialization hook should be called and call it. Throws an error if the hook contract
     * fails to execute the hook.
     *
     * @param config The encoded hooks configuration
     * @param exactAmountsInScaled18 An array with the initial liquidity of the pool
     * @param userData Additional (optional) data required for adding initial liquidity
     * @return success false if hook is disabled, true if hooks is enabled and succeeded to execute
     */
    function onBeforeInitialize(
        HooksConfig memory config,
        uint256[] memory exactAmountsInScaled18,
        bytes memory userData
    ) internal returns (bool) {
        if (config.shouldCallBeforeInitialize == false) {
            return false;
        }

        if (IHooks(config.hooksContract).onBeforeInitialize(exactAmountsInScaled18, userData) == false) {
            revert IVaultErrors.BeforeInitializeHookFailed();
        }
        return true;
    }

    /**
     * @dev Check if after initialization hook should be called and call it. Throws an error if the hook contract
     * fails to execute the hook.
     *
     * @param config The encoded hooks configuration
     * @param exactAmountsInScaled18 An array with the initial liquidity of the pool
     * @param bptAmountOut The BPT amount a user will receive after initialization operation succeeds
     * @param userData Additional (optional) data required for adding initial liquidity
     */
    function onAfterInitialize(
        HooksConfig memory config,
        uint256[] memory exactAmountsInScaled18,
        uint256 bptAmountOut,
        bytes memory userData
    ) internal {
        if (config.shouldCallAfterInitialize == false) {
            return;
        }

        if (IHooks(config.hooksContract).onAfterInitialize(exactAmountsInScaled18, bptAmountOut, userData) == false) {
            revert IVaultErrors.AfterInitializeHookFailed();
        }
    }
}
