// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { WordCodec } from "@balancer-labs/v3-solidity-utils/contracts/helpers/WordCodec.sol";

import { PoolConfigConst } from "./PoolConfigConst.sol";

/**
 * @notice Helper functions to read and write the packed hook configuration flags stored in `_poolConfigBits`.
 * @dev This library has two additional functions. `toHooksConfig` constructs a `HooksConfig` structure from the
 * PoolConfig and the hooks contract address. Also, there are `call<hook>` functions that forward the arguments
 * to the corresponding functions in the hook contract, then validate and return the results.
 *
 * Note that the entire configuration of each pool is stored in the `_poolConfigBits` mapping (one slot per pool).
 * This includes the data in the `PoolConfig` struct, plus the data in the `HookFlags` struct. The layout (i.e.,
 * offsets for each data field) is specified in `PoolConfigConst`.
 *
 * There are two libraries for interpreting these data. This one parses fields related to hooks, and also
 * contains helpers for the struct building and hooks contract forwarding functions described above. `PoolConfigLib`
 * contains helpers related to the non-hook-related flags, along with aggregate fee percentages and other data
 * associated with pools.
 *
 * The `PoolData` struct contains the raw bitmap with the entire pool state (`PoolConfigBits`), plus the token
 * configuration, scaling factors, and dynamic information such as current balances and rates.
 *
 * The hooks contract addresses themselves are stored in a separate `_hooksContracts` mapping.
 */
library HooksConfigLib {
    using WordCodec for bytes32;
    using HooksConfigLib for PoolConfigBits;

    // #region Bit offsets for hooks config

    function enableHookAdjustedAmounts(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(PoolConfigConst.ENABLE_HOOK_ADJUSTED_AMOUNTS_OFFSET);
    }

    function setHookAdjustedAmounts(PoolConfigBits config, bool value) internal pure returns (PoolConfigBits) {
        return
            PoolConfigBits.wrap(
                PoolConfigBits.unwrap(config).insertBool(value, PoolConfigConst.ENABLE_HOOK_ADJUSTED_AMOUNTS_OFFSET)
            );
    }

    function shouldCallBeforeInitialize(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(PoolConfigConst.BEFORE_INITIALIZE_OFFSET);
    }

    function setShouldCallBeforeInitialize(PoolConfigBits config, bool value) internal pure returns (PoolConfigBits) {
        return
            PoolConfigBits.wrap(
                PoolConfigBits.unwrap(config).insertBool(value, PoolConfigConst.BEFORE_INITIALIZE_OFFSET)
            );
    }

    function shouldCallAfterInitialize(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(PoolConfigConst.AFTER_INITIALIZE_OFFSET);
    }

    function setShouldCallAfterInitialize(PoolConfigBits config, bool value) internal pure returns (PoolConfigBits) {
        return
            PoolConfigBits.wrap(
                PoolConfigBits.unwrap(config).insertBool(value, PoolConfigConst.AFTER_INITIALIZE_OFFSET)
            );
    }

    function shouldCallComputeDynamicSwapFee(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(PoolConfigConst.DYNAMIC_SWAP_FEE_OFFSET);
    }

    function setShouldCallComputeDynamicSwapFee(
        PoolConfigBits config,
        bool value
    ) internal pure returns (PoolConfigBits) {
        return
            PoolConfigBits.wrap(
                PoolConfigBits.unwrap(config).insertBool(value, PoolConfigConst.DYNAMIC_SWAP_FEE_OFFSET)
            );
    }

    function shouldCallBeforeSwap(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(PoolConfigConst.BEFORE_SWAP_OFFSET);
    }

    function setShouldCallBeforeSwap(PoolConfigBits config, bool value) internal pure returns (PoolConfigBits) {
        return PoolConfigBits.wrap(PoolConfigBits.unwrap(config).insertBool(value, PoolConfigConst.BEFORE_SWAP_OFFSET));
    }

    function shouldCallAfterSwap(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(PoolConfigConst.AFTER_SWAP_OFFSET);
    }

    function setShouldCallAfterSwap(PoolConfigBits config, bool value) internal pure returns (PoolConfigBits) {
        return PoolConfigBits.wrap(PoolConfigBits.unwrap(config).insertBool(value, PoolConfigConst.AFTER_SWAP_OFFSET));
    }

    function shouldCallBeforeAddLiquidity(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(PoolConfigConst.BEFORE_ADD_LIQUIDITY_OFFSET);
    }

    function setShouldCallBeforeAddLiquidity(PoolConfigBits config, bool value) internal pure returns (PoolConfigBits) {
        return
            PoolConfigBits.wrap(
                PoolConfigBits.unwrap(config).insertBool(value, PoolConfigConst.BEFORE_ADD_LIQUIDITY_OFFSET)
            );
    }

    function shouldCallAfterAddLiquidity(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(PoolConfigConst.AFTER_ADD_LIQUIDITY_OFFSET);
    }

    function setShouldCallAfterAddLiquidity(PoolConfigBits config, bool value) internal pure returns (PoolConfigBits) {
        return
            PoolConfigBits.wrap(
                PoolConfigBits.unwrap(config).insertBool(value, PoolConfigConst.AFTER_ADD_LIQUIDITY_OFFSET)
            );
    }

    function shouldCallBeforeRemoveLiquidity(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(PoolConfigConst.BEFORE_REMOVE_LIQUIDITY_OFFSET);
    }

    function setShouldCallBeforeRemoveLiquidity(
        PoolConfigBits config,
        bool value
    ) internal pure returns (PoolConfigBits) {
        return
            PoolConfigBits.wrap(
                PoolConfigBits.unwrap(config).insertBool(value, PoolConfigConst.BEFORE_REMOVE_LIQUIDITY_OFFSET)
            );
    }

    function shouldCallAfterRemoveLiquidity(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(PoolConfigConst.AFTER_REMOVE_LIQUIDITY_OFFSET);
    }

    function setShouldCallAfterRemoveLiquidity(
        PoolConfigBits config,
        bool value
    ) internal pure returns (PoolConfigBits) {
        return
            PoolConfigBits.wrap(
                PoolConfigBits.unwrap(config).insertBool(value, PoolConfigConst.AFTER_REMOVE_LIQUIDITY_OFFSET)
            );
    }

    function toHooksConfig(PoolConfigBits config, IHooks hooksContract) internal pure returns (HooksConfig memory) {
        return
            HooksConfig({
                enableHookAdjustedAmounts: config.enableHookAdjustedAmounts(),
                shouldCallBeforeInitialize: config.shouldCallBeforeInitialize(),
                shouldCallAfterInitialize: config.shouldCallAfterInitialize(),
                shouldCallBeforeAddLiquidity: config.shouldCallBeforeAddLiquidity(),
                shouldCallAfterAddLiquidity: config.shouldCallAfterAddLiquidity(),
                shouldCallBeforeRemoveLiquidity: config.shouldCallBeforeRemoveLiquidity(),
                shouldCallAfterRemoveLiquidity: config.shouldCallAfterRemoveLiquidity(),
                shouldCallComputeDynamicSwapFee: config.shouldCallComputeDynamicSwapFee(),
                shouldCallBeforeSwap: config.shouldCallBeforeSwap(),
                shouldCallAfterSwap: config.shouldCallAfterSwap(),
                hooksContract: address(hooksContract)
            });
    }

    // #endregion

    // #region Hooks helper functions

    /**
     * @dev Call the `onComputeDynamicSwapFeePercentage` hook and return the result. Reverts on failure.
     * @param swapParams The swap parameters used to calculate the fee
     * @param pool Pool address
     * @param staticSwapFeePercentage Value of the static swap fee, for reference
     * @param hooksContract Storage slot with the address of the hooks contract
     * @return success false if hook is disabled, true if hooks is enabled and succeeded to execute
     * @return swapFeePercentage the calculated swap fee percentage. 0 if hook is disabled
     */
    function callComputeDynamicSwapFeeHook(
        PoolSwapParams memory swapParams,
        address pool,
        uint256 staticSwapFeePercentage,
        IHooks hooksContract
    ) internal view returns (bool, uint256) {
        (bool success, uint256 swapFeePercentage) = hooksContract.onComputeDynamicSwapFeePercentage(
            swapParams,
            pool,
            staticSwapFeePercentage
        );

        if (success == false) {
            revert IVaultErrors.DynamicSwapFeeHookFailed();
        }

        return (true, swapFeePercentage);
    }

    /**
     * @dev Call the `onBeforeSwap` hook. Reverts on failure.
     * @param swapParams The swap parameters used in the hook
     * @param pool Pool address
     * @param hooksContract Storage slot with the address of the hooks contract
     */
    function callBeforeSwapHook(PoolSwapParams memory swapParams, address pool, IHooks hooksContract) internal {
        if (hooksContract.onBeforeSwap(swapParams, pool) == false) {
            // Hook contract implements onBeforeSwap, but it has failed, so reverts the transaction.
            revert IVaultErrors.BeforeSwapHookFailed();
        }
    }

    /**
     * @dev Call the `onAfterSwap` hook, then validate and return the result. Reverts on failure, or if the limits
     * are violated. If the hook contract did not enable hook-adjusted amounts, it will ignore the hook results and
     * return the original `amountCalculatedRaw`.
     *
     * @param config The encoded pool configuration
     * @param amountCalculatedScaled18 Token amount calculated by the swap
     * @param amountCalculatedRaw Token amount calculated by the swap
     * @param router Router address
     * @param params The swap parameters
     * @param state Temporary state used in swap operations
     * @param poolData Struct containing balance and token information of the pool
     * @param hooksContract Storage slot with the address of the hooks contract
     * @return hookAdjustedAmountCalculatedRaw New amount calculated, potentially modified by the hook
     */
    function callAfterSwapHook(
        PoolConfigBits config,
        uint256 amountCalculatedScaled18,
        uint256 amountCalculatedRaw,
        address router,
        SwapParams memory params,
        SwapState memory state,
        PoolData memory poolData,
        IHooks hooksContract
    ) internal returns (uint256) {
        // Adjust balances for the AfterSwap hook.
        (uint256 amountInScaled18, uint256 amountOutScaled18) = params.kind == SwapKind.EXACT_IN
            ? (state.amountGivenScaled18, amountCalculatedScaled18)
            : (amountCalculatedScaled18, state.amountGivenScaled18);

        (bool success, uint256 hookAdjustedAmountCalculatedRaw) = hooksContract.onAfterSwap(
            AfterSwapParams({
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

        // If hook adjusted amounts is not enabled, ignore amounts returned by the hook
        if (config.enableHookAdjustedAmounts() == false) {
            return amountCalculatedRaw;
        }

        if (
            (params.kind == SwapKind.EXACT_IN && hookAdjustedAmountCalculatedRaw < params.limitRaw) ||
            (params.kind == SwapKind.EXACT_OUT && hookAdjustedAmountCalculatedRaw > params.limitRaw)
        ) {
            revert IVaultErrors.HookAdjustedSwapLimit(hookAdjustedAmountCalculatedRaw, params.limitRaw);
        }

        return hookAdjustedAmountCalculatedRaw;
    }

    /**
     * @dev Call the `onBeforeAddLiquidity` hook. Reverts on failure.
     * @param router Router address
     * @param maxAmountsInScaled18 An array with maximum amounts for each input token of the add liquidity operation
     * @param params The add liquidity parameters
     * @param poolData Struct containing balance and token information of the pool
     * @param hooksContract Storage slot with the address of the hooks contract
     */
    function callBeforeAddLiquidityHook(
        address router,
        uint256[] memory maxAmountsInScaled18,
        AddLiquidityParams memory params,
        PoolData memory poolData,
        IHooks hooksContract
    ) internal {
        if (
            hooksContract.onBeforeAddLiquidity(
                router,
                params.pool,
                params.kind,
                maxAmountsInScaled18,
                params.minBptAmountOut,
                poolData.balancesLiveScaled18,
                params.userData
            ) == false
        ) {
            revert IVaultErrors.BeforeAddLiquidityHookFailed();
        }
    }

    /**
     * @dev Call the `onAfterAddLiquidity` hook, then validate and return the result. Reverts on failure, or if
     * the limits are violated. If the contract did not enable hook-adjusted amounts, it will ignore the hook
     * results and return the original `amountsInRaw`.
     *
     * @param config The encoded pool configuration
     * @param router Router address
     * @param amountsInScaled18 An array with amounts for each input token of the add liquidity operation
     * @param amountsInRaw An array with amounts for each input token of the add liquidity operation
     * @param bptAmountOut The BPT amount a user will receive after add liquidity operation succeeds
     * @param params The add liquidity parameters
     * @param poolData Struct containing balance and token information of the pool
     * @param hooksContract Storage slot with the address of the hooks contract
     * @return hookAdjustedAmountsInRaw New amountsInRaw, potentially modified by the hook
     */
    function callAfterAddLiquidityHook(
        PoolConfigBits config,
        address router,
        uint256[] memory amountsInScaled18,
        uint256[] memory amountsInRaw,
        uint256 bptAmountOut,
        AddLiquidityParams memory params,
        PoolData memory poolData,
        IHooks hooksContract
    ) internal returns (uint256[] memory) {
        (bool success, uint256[] memory hookAdjustedAmountsInRaw) = hooksContract.onAfterAddLiquidity(
            router,
            params.pool,
            params.kind,
            amountsInScaled18,
            amountsInRaw,
            bptAmountOut,
            poolData.balancesLiveScaled18,
            params.userData
        );

        if (success == false || hookAdjustedAmountsInRaw.length != amountsInRaw.length) {
            revert IVaultErrors.AfterAddLiquidityHookFailed();
        }

        // If hook adjusted amounts is not enabled, ignore amounts returned by the hook
        if (config.enableHookAdjustedAmounts() == false) {
            return amountsInRaw;
        }

        for (uint256 i = 0; i < hookAdjustedAmountsInRaw.length; i++) {
            if (hookAdjustedAmountsInRaw[i] > params.maxAmountsIn[i]) {
                revert IVaultErrors.HookAdjustedAmountInAboveMax(
                    poolData.tokens[i],
                    hookAdjustedAmountsInRaw[i],
                    params.maxAmountsIn[i]
                );
            }
        }

        return hookAdjustedAmountsInRaw;
    }

    /**
     * @dev Call the `onBeforeRemoveLiquidity` hook. Reverts on failure.
     * @param minAmountsOutScaled18 Minimum amounts for each output token of the remove liquidity operation
     * @param router Router address
     * @param params The remove liquidity parameters
     * @param poolData Struct containing balance and token information of the pool
     * @param hooksContract Storage slot with the address of the hooks contract
     */
    function callBeforeRemoveLiquidityHook(
        uint256[] memory minAmountsOutScaled18,
        address router,
        RemoveLiquidityParams memory params,
        PoolData memory poolData,
        IHooks hooksContract
    ) internal {
        if (
            hooksContract.onBeforeRemoveLiquidity(
                router,
                params.pool,
                params.kind,
                params.maxBptAmountIn,
                minAmountsOutScaled18,
                poolData.balancesLiveScaled18,
                params.userData
            ) == false
        ) {
            revert IVaultErrors.BeforeRemoveLiquidityHookFailed();
        }
    }

    /**
     * @dev Call the `onAfterRemoveLiquidity` hook, then validate and return the result. Reverts on failure, or if
     * the limits are violated. If the contract did not enable hook-adjusted amounts, it will ignore the hook
     * results and return the original `amountsOutRaw`.
     *
     * @param config The encoded pool configuration
     * @param router Router address
     * @param amountsOutScaled18 Scaled amount of tokens to receive, sorted in token registration order
     * @param amountsOutRaw Actual amount of tokens to receive, sorted in token registration order
     * @param bptAmountIn The BPT amount a user will need burn to remove the liquidity of the pool
     * @param params The remove liquidity parameters
     * @param poolData Struct containing balance and token information of the pool
     * @param hooksContract Storage slot with the address of the hooks contract
     * @return hookAdjustedAmountsOutRaw New amountsOutRaw, potentially modified by the hook
     */
    function callAfterRemoveLiquidityHook(
        PoolConfigBits config,
        address router,
        uint256[] memory amountsOutScaled18,
        uint256[] memory amountsOutRaw,
        uint256 bptAmountIn,
        RemoveLiquidityParams memory params,
        PoolData memory poolData,
        IHooks hooksContract
    ) internal returns (uint256[] memory) {
        (bool success, uint256[] memory hookAdjustedAmountsOutRaw) = hooksContract.onAfterRemoveLiquidity(
            router,
            params.pool,
            params.kind,
            bptAmountIn,
            amountsOutScaled18,
            amountsOutRaw,
            poolData.balancesLiveScaled18,
            params.userData
        );

        if (success == false || hookAdjustedAmountsOutRaw.length != amountsOutRaw.length) {
            revert IVaultErrors.AfterRemoveLiquidityHookFailed();
        }

        // If hook adjusted amounts is not enabled, ignore amounts returned by the hook
        if (config.enableHookAdjustedAmounts() == false) {
            return amountsOutRaw;
        }

        for (uint256 i = 0; i < hookAdjustedAmountsOutRaw.length; i++) {
            if (hookAdjustedAmountsOutRaw[i] < params.minAmountsOut[i]) {
                revert IVaultErrors.HookAdjustedAmountOutBelowMin(
                    poolData.tokens[i],
                    hookAdjustedAmountsOutRaw[i],
                    params.minAmountsOut[i]
                );
            }
        }

        return hookAdjustedAmountsOutRaw;
    }

    /**
     * @dev Call the `onBeforeInitialize` hook. Reverts on failure.
     * @param exactAmountsInScaled18 An array with the initial liquidity of the pool
     * @param userData Additional (optional) data required for adding initial liquidity
     * @param hooksContract Storage slot with the address of the hooks contract
     */
    function callBeforeInitializeHook(
        uint256[] memory exactAmountsInScaled18,
        bytes memory userData,
        IHooks hooksContract
    ) internal {
        if (hooksContract.onBeforeInitialize(exactAmountsInScaled18, userData) == false) {
            revert IVaultErrors.BeforeInitializeHookFailed();
        }
    }

    /**
     * @dev Call the `onAfterInitialize` hook. Reverts on failure.
     * @param exactAmountsInScaled18 An array with the initial liquidity of the pool
     * @param bptAmountOut The BPT amount a user will receive after initialization operation succeeds
     * @param userData Additional (optional) data required for adding initial liquidity
     * @param hooksContract Storage slot with the address of the hooks contract
     */
    function callAfterInitializeHook(
        uint256[] memory exactAmountsInScaled18,
        uint256 bptAmountOut,
        bytes memory userData,
        IHooks hooksContract
    ) internal {
        if (hooksContract.onAfterInitialize(exactAmountsInScaled18, bptAmountOut, userData) == false) {
            revert IVaultErrors.AfterInitializeHookFailed();
        }
    }

    // #endregion
}
