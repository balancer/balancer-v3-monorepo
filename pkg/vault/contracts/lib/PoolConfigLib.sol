// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { WordCodec } from "@balancer-labs/v3-solidity-utils/contracts/helpers/WordCodec.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

library PoolConfigLib {
    using WordCodec for bytes32;
    using PoolConfigLib for PoolConfigBits;

    error InvalidSize(uint256 currentValue, uint256 expectedSize);

    // Bit offsets for main pool config settings
    uint8 public constant POOL_REGISTERED_OFFSET = 0;
    uint8 public constant POOL_INITIALIZED_OFFSET = POOL_REGISTERED_OFFSET + 1;
    uint8 public constant POOL_PAUSED_OFFSET = POOL_INITIALIZED_OFFSET + 1;
    uint8 public constant POOL_RECOVERY_MODE_OFFSET = POOL_PAUSED_OFFSET + 1;

    // Bit offsets for liquidity operations
    uint8 public constant UNBALANCED_LIQUIDITY_OFFSET = POOL_RECOVERY_MODE_OFFSET + 1;
    uint8 public constant ADD_LIQUIDITY_CUSTOM_OFFSET = UNBALANCED_LIQUIDITY_OFFSET + 1;
    uint8 public constant REMOVE_LIQUIDITY_CUSTOM_OFFSET = ADD_LIQUIDITY_CUSTOM_OFFSET + 1;

    // Bit offsets for hooks config
    uint8 public constant ANY_INITIALIZE_HOOK_ENABLED_OFFSET = REMOVE_LIQUIDITY_CUSTOM_OFFSET + 1;
    uint8 public constant ANY_SWAP_HOOK_ENABLED_OFFSET = ANY_INITIALIZE_HOOK_ENABLED_OFFSET + 1;
    uint8 public constant ANY_ADD_LIQUIDITY_HOOK_ENABLED_OFFSET = ANY_SWAP_HOOK_ENABLED_OFFSET + 1;
    uint8 public constant ANY_REMOVE_LIQUIDITY_HOOK_ENABLED_OFFSET = ANY_ADD_LIQUIDITY_HOOK_ENABLED_OFFSET + 1;
    uint8 public constant BEFORE_INITIALIZE_OFFSET = ANY_REMOVE_LIQUIDITY_HOOK_ENABLED_OFFSET + 1;
    uint8 public constant ENABLE_HOOK_ADJUSTED_AMOUNTS_OFFSET = BEFORE_INITIALIZE_OFFSET + 1;
    uint8 public constant AFTER_INITIALIZE_OFFSET = ENABLE_HOOK_ADJUSTED_AMOUNTS_OFFSET + 1;
    uint8 public constant DYNAMIC_SWAP_FEE_OFFSET = AFTER_INITIALIZE_OFFSET + 1;
    uint8 public constant BEFORE_SWAP_OFFSET = DYNAMIC_SWAP_FEE_OFFSET + 1;
    uint8 public constant AFTER_SWAP_OFFSET = BEFORE_SWAP_OFFSET + 1;
    uint8 public constant BEFORE_ADD_LIQUIDITY_OFFSET = AFTER_SWAP_OFFSET + 1;
    uint8 public constant AFTER_ADD_LIQUIDITY_OFFSET = BEFORE_ADD_LIQUIDITY_OFFSET + 1;
    uint8 public constant BEFORE_REMOVE_LIQUIDITY_OFFSET = AFTER_ADD_LIQUIDITY_OFFSET + 1;
    uint8 public constant AFTER_REMOVE_LIQUIDITY_OFFSET = BEFORE_REMOVE_LIQUIDITY_OFFSET + 1;

    // Bit offsets for uint values
    uint8 public constant STATIC_SWAP_FEE_OFFSET = AFTER_REMOVE_LIQUIDITY_OFFSET + 1;
    uint256 public constant AGGREGATE_SWAP_FEE_OFFSET = STATIC_SWAP_FEE_OFFSET + FEE_BITLENGTH;
    uint256 public constant AGGREGATE_YIELD_FEE_OFFSET = AGGREGATE_SWAP_FEE_OFFSET + FEE_BITLENGTH;
    uint256 public constant DECIMAL_SCALING_FACTORS_OFFSET = AGGREGATE_YIELD_FEE_OFFSET + FEE_BITLENGTH;
    uint256 public constant PAUSE_WINDOW_END_TIME_OFFSET =
        DECIMAL_SCALING_FACTORS_OFFSET + _TOKEN_DECIMAL_DIFFS_BITLENGTH;

    // Uses a uint24 (3 bytes): least significant 20 bits to store the values, and a 4-bit pad.
    // This maximum token count is also hard-coded in the Vault.
    uint8 private constant _TOKEN_DECIMAL_DIFFS_BITLENGTH = 24;
    uint8 private constant _DECIMAL_DIFF_BITLENGTH = 5;

    uint8 private constant _TIMESTAMP_BITLENGTH = 32;

    // #region Bit offsets for main pool config settings
    function isAnyInitializeHookEnabled(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(ANY_INITIALIZE_HOOK_ENABLED_OFFSET);
    }

    function setAnyInitializeHookEnabled(PoolConfigBits config, bool value) internal pure returns (PoolConfigBits) {
        return PoolConfigBits.wrap(PoolConfigBits.unwrap(config).insertBool(value, ANY_INITIALIZE_HOOK_ENABLED_OFFSET));
    }

    function isAnySwapHookEnabled(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(ANY_SWAP_HOOK_ENABLED_OFFSET);
    }

    function setAnySwapHookEnabled(PoolConfigBits config, bool value) internal pure returns (PoolConfigBits) {
        return PoolConfigBits.wrap(PoolConfigBits.unwrap(config).insertBool(value, ANY_SWAP_HOOK_ENABLED_OFFSET));
    }

    function isAnyAddLiquidityHookEnabled(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(ANY_ADD_LIQUIDITY_HOOK_ENABLED_OFFSET);
    }

    function setAnyAddLiquidityHookEnabled(PoolConfigBits config, bool value) internal pure returns (PoolConfigBits) {
        return
            PoolConfigBits.wrap(PoolConfigBits.unwrap(config).insertBool(value, ANY_ADD_LIQUIDITY_HOOK_ENABLED_OFFSET));
    }

    function isAnyRemoveLiquidityHookEnabled(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(ANY_REMOVE_LIQUIDITY_HOOK_ENABLED_OFFSET);
    }

    function setAnyRemoveLiquidityHookEnabled(
        PoolConfigBits config,
        bool value
    ) internal pure returns (PoolConfigBits) {
        return
            PoolConfigBits.wrap(
                PoolConfigBits.unwrap(config).insertBool(value, ANY_REMOVE_LIQUIDITY_HOOK_ENABLED_OFFSET)
            );
    }

    function isPoolRegistered(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(POOL_REGISTERED_OFFSET);
    }

    function setPoolRegistered(PoolConfigBits config, bool value) internal pure returns (PoolConfigBits) {
        return PoolConfigBits.wrap(PoolConfigBits.unwrap(config).insertBool(value, POOL_REGISTERED_OFFSET));
    }

    function isPoolInitialized(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(POOL_INITIALIZED_OFFSET);
    }

    function setPoolInitialized(PoolConfigBits config, bool value) internal pure returns (PoolConfigBits) {
        return PoolConfigBits.wrap(PoolConfigBits.unwrap(config).insertBool(value, POOL_INITIALIZED_OFFSET));
    }

    function isPoolPaused(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(POOL_PAUSED_OFFSET);
    }

    function setPoolPaused(PoolConfigBits config, bool value) internal pure returns (PoolConfigBits) {
        return PoolConfigBits.wrap(PoolConfigBits.unwrap(config).insertBool(value, POOL_PAUSED_OFFSET));
    }

    function isPoolInRecoveryMode(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(POOL_RECOVERY_MODE_OFFSET);
    }

    function setPoolInRecoveryMode(PoolConfigBits config, bool value) internal pure returns (PoolConfigBits) {
        return PoolConfigBits.wrap(PoolConfigBits.unwrap(config).insertBool(value, POOL_RECOVERY_MODE_OFFSET));
    }

    // #endregion

    // #region Bit offsets for liquidity operations
    function supportsUnbalancedLiquidity(PoolConfigBits config) internal pure returns (bool) {
        // NOTE: The unbalanced liquidity flag is default-on (false means it is supported).
        // This function returns the inverted value.
        return !PoolConfigBits.unwrap(config).decodeBool(UNBALANCED_LIQUIDITY_OFFSET);
    }

    function requireUnbalancedLiquidityEnabled(PoolConfigBits config) internal pure {
        if (config.supportsUnbalancedLiquidity() == false) {
            revert IVaultErrors.DoesNotSupportUnbalancedLiquidity();
        }
    }

    function setDisableUnbalancedLiquidity(
        PoolConfigBits config,
        bool disableUnbalancedLiquidity
    ) internal pure returns (PoolConfigBits) {
        return
            PoolConfigBits.wrap(
                PoolConfigBits.unwrap(config).insertBool(disableUnbalancedLiquidity, UNBALANCED_LIQUIDITY_OFFSET)
            );
    }

    function supportsAddLiquidityCustom(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(ADD_LIQUIDITY_CUSTOM_OFFSET);
    }

    function requireAddCustomLiquidityEnabled(PoolConfigBits config) internal pure {
        if (config.supportsAddLiquidityCustom() == false) {
            revert IVaultErrors.DoesNotSupportAddLiquidityCustom();
        }
    }

    function setAddLiquidityCustom(
        PoolConfigBits config,
        bool enableAddLiquidityCustom
    ) internal pure returns (PoolConfigBits) {
        return
            PoolConfigBits.wrap(
                PoolConfigBits.unwrap(config).insertBool(enableAddLiquidityCustom, ADD_LIQUIDITY_CUSTOM_OFFSET)
            );
    }

    function supportsRemoveLiquidityCustom(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(REMOVE_LIQUIDITY_CUSTOM_OFFSET);
    }

    function requireRemoveCustomLiquidityEnabled(PoolConfigBits config) internal pure {
        if (config.supportsRemoveLiquidityCustom() == false) {
            revert IVaultErrors.DoesNotSupportRemoveLiquidityCustom();
        }
    }

    function setRemoveLiquidityCustom(
        PoolConfigBits config,
        bool enableRemoveLiquidityCustom
    ) internal pure returns (PoolConfigBits) {
        return
            PoolConfigBits.wrap(
                PoolConfigBits.unwrap(config).insertBool(enableRemoveLiquidityCustom, REMOVE_LIQUIDITY_CUSTOM_OFFSET)
            );
    }

    // #endregion

    // #region Bit offsets for hooks config
    function enableHookAdjustedAmounts(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(ENABLE_HOOK_ADJUSTED_AMOUNTS_OFFSET);
    }

    function setHookAdjustedAmounts(PoolConfigBits config, bool value) internal pure returns (PoolConfigBits) {
        return
            PoolConfigBits.wrap(PoolConfigBits.unwrap(config).insertBool(value, ENABLE_HOOK_ADJUSTED_AMOUNTS_OFFSET));
    }

    function shouldCallBeforeInitialize(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(BEFORE_INITIALIZE_OFFSET);
    }

    function setShouldCallBeforeInitialize(PoolConfigBits config, bool value) internal pure returns (PoolConfigBits) {
        return PoolConfigBits.wrap(PoolConfigBits.unwrap(config).insertBool(value, BEFORE_INITIALIZE_OFFSET));
    }

    function shouldCallAfterInitialize(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(AFTER_INITIALIZE_OFFSET);
    }

    function setShouldCallAfterInitialize(PoolConfigBits config, bool value) internal pure returns (PoolConfigBits) {
        return PoolConfigBits.wrap(PoolConfigBits.unwrap(config).insertBool(value, AFTER_INITIALIZE_OFFSET));
    }

    function shouldCallComputeDynamicSwapFee(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(DYNAMIC_SWAP_FEE_OFFSET);
    }

    function setShouldCallComputeDynamicSwapFee(
        PoolConfigBits config,
        bool value
    ) internal pure returns (PoolConfigBits) {
        return PoolConfigBits.wrap(PoolConfigBits.unwrap(config).insertBool(value, DYNAMIC_SWAP_FEE_OFFSET));
    }

    function shouldCallBeforeSwap(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(BEFORE_SWAP_OFFSET);
    }

    function setShouldCallBeforeSwap(PoolConfigBits config, bool value) internal pure returns (PoolConfigBits) {
        return PoolConfigBits.wrap(PoolConfigBits.unwrap(config).insertBool(value, BEFORE_SWAP_OFFSET));
    }

    function shouldCallAfterSwap(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(AFTER_SWAP_OFFSET);
    }

    function setShouldCallAfterSwap(PoolConfigBits config, bool value) internal pure returns (PoolConfigBits) {
        return PoolConfigBits.wrap(PoolConfigBits.unwrap(config).insertBool(value, AFTER_SWAP_OFFSET));
    }

    function shouldCallBeforeAddLiquidity(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(BEFORE_ADD_LIQUIDITY_OFFSET);
    }

    function setShouldCallBeforeAddLiquidity(PoolConfigBits config, bool value) internal pure returns (PoolConfigBits) {
        return PoolConfigBits.wrap(PoolConfigBits.unwrap(config).insertBool(value, BEFORE_ADD_LIQUIDITY_OFFSET));
    }

    function shouldCallAfterAddLiquidity(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(AFTER_ADD_LIQUIDITY_OFFSET);
    }

    function setShouldCallAfterAddLiquidity(PoolConfigBits config, bool value) internal pure returns (PoolConfigBits) {
        return PoolConfigBits.wrap(PoolConfigBits.unwrap(config).insertBool(value, AFTER_ADD_LIQUIDITY_OFFSET));
    }

    function shouldCallBeforeRemoveLiquidity(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(BEFORE_REMOVE_LIQUIDITY_OFFSET);
    }

    function setShouldCallBeforeRemoveLiquidity(
        PoolConfigBits config,
        bool value
    ) internal pure returns (PoolConfigBits) {
        return PoolConfigBits.wrap(PoolConfigBits.unwrap(config).insertBool(value, BEFORE_REMOVE_LIQUIDITY_OFFSET));
    }

    function shouldCallAfterRemoveLiquidity(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(AFTER_REMOVE_LIQUIDITY_OFFSET);
    }

    function setShouldCallAfterRemoveLiquidity(
        PoolConfigBits config,
        bool value
    ) internal pure returns (PoolConfigBits) {
        return PoolConfigBits.wrap(PoolConfigBits.unwrap(config).insertBool(value, AFTER_REMOVE_LIQUIDITY_OFFSET));
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

    /**
     * @dev Check if dynamic swap fee hook should be called and call it. Throws an error if the hook contract fails to
     * execute the hook.
     *
     * @param config The encoded hooks configuration
     * @param swapParams The swap parameters used to calculate the fee
     * @param staticSwapFeePercentage Value of the static swap fee, for reference
     * @return success false if hook is disabled, true if hooks is enabled and succeeded to execute
     * @return swapFeePercentage the calculated swap fee percentage. 0 if hook is disabled
     */
    function callComputeDynamicSwapFeeHook(
        PoolConfigBits config,
        IBasePool.PoolSwapParams memory swapParams,
        uint256 staticSwapFeePercentage,
        IHooks hooksContract
    ) internal view returns (bool, uint256) {
        if (config.shouldCallComputeDynamicSwapFee() == false) {
            return (false, staticSwapFeePercentage);
        }

        (bool success, uint256 swapFeePercentage) = hooksContract.onComputeDynamicSwapFee(
            swapParams,
            staticSwapFeePercentage
        );

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
    function callBeforeSwapHook(
        PoolConfigBits config,
        IBasePool.PoolSwapParams memory swapParams,
        address pool,
        IHooks hooksContract
    ) internal returns (bool) {
        if (config.shouldCallBeforeSwap() == false) {
            // Hook contract does not implement onBeforeSwap, so success is false (hook was not executed)
            return false;
        }

        if (hooksContract.onBeforeSwap(swapParams, pool) == false) {
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
     * @param router Router address
     * @param params The swap parameters
     * @param state Temporary state used in swap operations
     * @param poolData Struct containing balance and token information of the pool
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
        if (config.shouldCallAfterSwap() == false) {
            // Hook contract does not implement onAfterSwap, so success is false (hook was not executed) and do not
            // change amountCalculatedRaw (no deltas)
            return amountCalculatedRaw;
        }

        // Adjust balances for the AfterSwap hook.
        (uint256 amountInScaled18, uint256 amountOutScaled18) = params.kind == SwapKind.EXACT_IN
            ? (state.amountGivenScaled18, amountCalculatedScaled18)
            : (amountCalculatedScaled18, state.amountGivenScaled18);

        (bool success, uint256 hookAdjustedAmountCalculatedRaw) = hooksContract.onAfterSwap(
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
     * @dev Check if before add liquidity hook should be called and call it. Throws an error if the hook contract fails
     * to execute the hook.
     *
     * @param config The encoded hooks configuration
     * @param router Router address
     * @param maxAmountsInScaled18 An array with maximum amounts for each input token of the add liquidity operation
     * @param params The add liquidity parameters
     * @param poolData Struct containing balance and token information of the pool
     * @return success false if hook is disabled, true if hooks is enabled and succeeded to execute
     */
    function callBeforeAddLiquidityHook(
        PoolConfigBits config,
        address router,
        uint256[] memory maxAmountsInScaled18,
        AddLiquidityParams memory params,
        PoolData memory poolData,
        IHooks hooksContract
    ) internal returns (bool) {
        if (config.shouldCallBeforeAddLiquidity() == false) {
            return false;
        }

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
        return true;
    }

    /**
     * @dev Check if after add liquidity hook should be called and call it. Throws an error if the hook contract fails
     * to execute the hook.
     *
     * @param config The encoded hooks configuration
     * @param router Router address
     * @param amountsInScaled18 An array with amounts for each input token of the add liquidity operation
     * @param amountsInRaw An array with amounts for each input token of the add liquidity operation
     * @param bptAmountOut The BPT amount a user will receive after add liquidity operation succeeds
     * @param params The add liquidity parameters
     * @param poolData Struct containing balance and token information of the pool
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
        if (config.shouldCallAfterAddLiquidity() == false) {
            return amountsInRaw;
        }

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

        if (success == false) {
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
     * @dev Check if before remove liquidity hook should be called and call it. Throws an error if the hook contract
     * fails to execute the hook.
     *
     * @param config The encoded hooks configuration
     * @param minAmountsOutScaled18 An array with minimum amounts for each output token of the remove liquidity
     * operation
     * @param router Router address
     * @param params The remove liquidity parameters
     * @param poolData Struct containing balance and token information of the pool
     * @return success false if hook is disabled, true if hooks is enabled and succeeded to execute
     */
    function callBeforeRemoveLiquidityHook(
        PoolConfigBits config,
        uint256[] memory minAmountsOutScaled18,
        address router,
        RemoveLiquidityParams memory params,
        PoolData memory poolData,
        IHooks hooksContract
    ) internal returns (bool) {
        if (config.shouldCallBeforeRemoveLiquidity() == false) {
            return false;
        }

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
        return true;
    }

    /**
     * @dev Check if after remove liquidity hook should be called and call it. Throws an error if the hook contract
     * fails to execute the hook.
     * @param config The encoded hooks configuration
     * @param router Router address
     * @param amountsOutScaled18 Scaled amount of tokens to receive, sorted in token registration order
     * @param amountsOutRaw Actual amount of tokens to receive, sorted in token registration order
     * @param bptAmountIn The BPT amount a user will need burn to remove the liquidity of the pool
     * @param params The remove liquidity parameters
     * @param poolData Struct containing balance and token information of the pool
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
        if (config.shouldCallAfterRemoveLiquidity() == false) {
            return amountsOutRaw;
        }

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

        if (success == false) {
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
     * @dev Check if before initialization hook should be called and call it. Throws an error if the hook contract
     * fails to execute the hook.
     *
     * @param config The encoded hooks configuration
     * @param exactAmountsInScaled18 An array with the initial liquidity of the pool
     * @param userData Additional (optional) data required for adding initial liquidity
     * @return success false if hook is disabled, true if hooks is enabled and succeeded to execute
     */
    function callBeforeInitializeHook(
        PoolConfigBits config,
        uint256[] memory exactAmountsInScaled18,
        bytes memory userData,
        IHooks hooksContract
    ) internal returns (bool) {
        if (config.shouldCallBeforeInitialize() == false) {
            return false;
        }

        if (hooksContract.onBeforeInitialize(exactAmountsInScaled18, userData) == false) {
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
    function callAfterInitializeHook(
        PoolConfigBits config,
        uint256[] memory exactAmountsInScaled18,
        uint256 bptAmountOut,
        bytes memory userData,
        IHooks hooksContract
    ) internal {
        if (config.shouldCallAfterInitialize() == false) {
            return;
        }

        if (hooksContract.onAfterInitialize(exactAmountsInScaled18, bptAmountOut, userData) == false) {
            revert IVaultErrors.AfterInitializeHookFailed();
        }
    }

    // #endregion

    // #region Bit offsets for uint values
    function getStaticSwapFeePercentage(PoolConfigBits config) internal pure returns (uint256) {
        return PoolConfigBits.unwrap(config).decodeUint(STATIC_SWAP_FEE_OFFSET, FEE_BITLENGTH) * FEE_SCALING_FACTOR;
    }

    function setStaticSwapFeePercentage(PoolConfigBits config, uint256 value) internal pure returns (PoolConfigBits) {
        value /= FEE_SCALING_FACTOR;

        if (value > MAX_FEE_VALUE) {
            revert InvalidSize(value, FEE_BITLENGTH);
        }

        return
            PoolConfigBits.wrap(PoolConfigBits.unwrap(config).insertUint(value, STATIC_SWAP_FEE_OFFSET, FEE_BITLENGTH));
    }

    function getAggregateSwapFeePercentage(PoolConfigBits config) internal pure returns (uint256) {
        return PoolConfigBits.unwrap(config).decodeUint(AGGREGATE_SWAP_FEE_OFFSET, FEE_BITLENGTH) * FEE_SCALING_FACTOR;
    }

    function setAggregateSwapFeePercentage(
        PoolConfigBits config,
        uint256 value
    ) internal pure returns (PoolConfigBits) {
        value /= FEE_SCALING_FACTOR;

        if (value > MAX_FEE_VALUE) {
            revert InvalidSize(value, FEE_BITLENGTH);
        }

        return
            PoolConfigBits.wrap(
                PoolConfigBits.unwrap(config).insertUint(value, AGGREGATE_SWAP_FEE_OFFSET, FEE_BITLENGTH)
            );
    }

    function getAggregateYieldFeePercentage(PoolConfigBits config) internal pure returns (uint256) {
        return PoolConfigBits.unwrap(config).decodeUint(AGGREGATE_YIELD_FEE_OFFSET, FEE_BITLENGTH) * FEE_SCALING_FACTOR;
    }

    function setAggregateYieldFeePercentage(
        PoolConfigBits config,
        uint256 value
    ) internal pure returns (PoolConfigBits) {
        value /= FEE_SCALING_FACTOR;

        if (value > MAX_FEE_VALUE) {
            revert InvalidSize(value, FEE_BITLENGTH);
        }

        return
            PoolConfigBits.wrap(
                PoolConfigBits.unwrap(config).insertUint(value, AGGREGATE_YIELD_FEE_OFFSET, FEE_BITLENGTH)
            );
    }

    function getTokenDecimalDiffs(PoolConfigBits config) internal pure returns (uint24) {
        return
            uint24(
                PoolConfigBits.unwrap(config).decodeUint(DECIMAL_SCALING_FACTORS_OFFSET, _TOKEN_DECIMAL_DIFFS_BITLENGTH)
            );
    }

    function getDecimalScalingFactors(
        PoolConfigBits config,
        uint256 numTokens
    ) internal pure returns (uint256[] memory) {
        uint256[] memory scalingFactors = new uint256[](numTokens);

        bytes32 tokenDecimalDiffs = bytes32(uint256(config.getTokenDecimalDiffs()));

        for (uint256 i = 0; i < numTokens; ++i) {
            uint256 decimalDiff = tokenDecimalDiffs.decodeUint(i * _DECIMAL_DIFF_BITLENGTH, _DECIMAL_DIFF_BITLENGTH);

            // This is equivalent to `10**(18+decimalsDifference)` but this form optimizes for 18 decimal tokens.
            scalingFactors[i] = FixedPoint.ONE * 10 ** decimalDiff;
        }

        return scalingFactors;
    }

    function setTokenDecimalDiffs(PoolConfigBits config, uint24 value) internal pure returns (PoolConfigBits) {
        return
            PoolConfigBits.wrap(
                PoolConfigBits.unwrap(config).insertUint(
                    value,
                    DECIMAL_SCALING_FACTORS_OFFSET,
                    _TOKEN_DECIMAL_DIFFS_BITLENGTH
                )
            );
    }

    function getPauseWindowEndTime(PoolConfigBits config) internal pure returns (uint32) {
        return uint32(PoolConfigBits.unwrap(config).decodeUint(PAUSE_WINDOW_END_TIME_OFFSET, _TIMESTAMP_BITLENGTH));
    }

    function setPauseWindowEndTime(PoolConfigBits config, uint32 value) internal pure returns (PoolConfigBits) {
        return
            PoolConfigBits.wrap(
                PoolConfigBits.unwrap(config).insertUint(value, PAUSE_WINDOW_END_TIME_OFFSET, _TIMESTAMP_BITLENGTH)
            );
    }

    // #endregion

    // Convert from an array of decimal differences, to the encoded 24 bit value (only uses bottom 20 bits).
    function toTokenDecimalDiffs(uint8[] memory tokenDecimalDiffs) internal pure returns (uint24) {
        bytes32 value;

        for (uint256 i = 0; i < tokenDecimalDiffs.length; ++i) {
            value = value.insertUint(tokenDecimalDiffs[i], i * _DECIMAL_DIFF_BITLENGTH, _DECIMAL_DIFF_BITLENGTH);
        }

        return uint24(uint256(value));
    }
}
