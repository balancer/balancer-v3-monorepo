// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { WordCodec } from "@balancer-labs/v3-solidity-utils/contracts/helpers/WordCodec.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

library HooksConfigLib {
    using WordCodec for bytes32;
    using HooksConfigLib for HooksConfigBits;

    // Bit offsets for pool config

    uint8 public constant BEFORE_INITIALIZE_OFFSET = 0;
    uint8 public constant AFTER_INITIALIZE_OFFSET = BEFORE_INITIALIZE_OFFSET + 1;
    uint8 public constant DYNAMIC_SWAP_FEE_OFFSET = AFTER_INITIALIZE_OFFSET + 1;
    uint8 public constant BEFORE_SWAP_OFFSET = DYNAMIC_SWAP_FEE_OFFSET + 1;
    uint8 public constant AFTER_SWAP_OFFSET = BEFORE_SWAP_OFFSET + 1;
    uint8 public constant BEFORE_ADD_LIQUIDITY_OFFSET = AFTER_SWAP_OFFSET + 1;
    uint8 public constant AFTER_ADD_LIQUIDITY_OFFSET = BEFORE_ADD_LIQUIDITY_OFFSET + 1;
    uint8 public constant BEFORE_REMOVE_LIQUIDITY_OFFSET = AFTER_ADD_LIQUIDITY_OFFSET + 1;
    uint8 public constant AFTER_REMOVE_LIQUIDITY_OFFSET = BEFORE_REMOVE_LIQUIDITY_OFFSET + 1;
    uint8 public constant HOOKS_CONTRACT_OFFSET = AFTER_REMOVE_LIQUIDITY_OFFSET + 1;

    function shouldCallBeforeInitialize(HooksConfigBits memory config) internal pure returns (bool) {
        return config.bits.decodeBool(BEFORE_INITIALIZE_OFFSET);
    }

    function setShouldCallBeforeInitialize(HooksConfigBits memory config, bool value) internal pure {
        config.bits = config.bits.insertBool(value, BEFORE_INITIALIZE_OFFSET);
    }

    function shouldCallAfterInitialize(HooksConfigBits memory config) internal pure returns (bool) {
        return config.bits.decodeBool(AFTER_INITIALIZE_OFFSET);
    }

    function setShouldCallAfterInitialize(HooksConfigBits memory config, bool value) internal pure {
        config.bits = config.bits.insertBool(value, AFTER_INITIALIZE_OFFSET);
    }

    function shouldCallComputeDynamicSwapFee(HooksConfigBits memory config) internal pure returns (bool) {
        return config.bits.decodeBool(DYNAMIC_SWAP_FEE_OFFSET);
    }

    function setShouldCallComputeDynamicSwapFee(HooksConfigBits memory config, bool value) internal pure {
        config.bits = config.bits.insertBool(value, DYNAMIC_SWAP_FEE_OFFSET);
    }

    function shouldCallBeforeSwap(HooksConfigBits memory config) internal pure returns (bool) {
        return config.bits.decodeBool(BEFORE_SWAP_OFFSET);
    }

    function setShouldCallBeforeSwap(HooksConfigBits memory config, bool value) internal pure {
        config.bits = config.bits.insertBool(value, BEFORE_SWAP_OFFSET);
    }

    function shouldCallAfterSwap(HooksConfigBits memory config) internal pure returns (bool) {
        return config.bits.decodeBool(AFTER_SWAP_OFFSET);
    }

    function setShouldCallAfterSwap(HooksConfigBits memory config, bool value) internal pure {
        config.bits = config.bits.insertBool(value, AFTER_SWAP_OFFSET);
    }

    function shouldCallBeforeAddLiquidity(HooksConfigBits memory config) internal pure returns (bool) {
        return config.bits.decodeBool(BEFORE_ADD_LIQUIDITY_OFFSET);
    }

    function setShouldCallBeforeAddLiquidity(HooksConfigBits memory config, bool value) internal pure {
        config.bits = config.bits.insertBool(value, BEFORE_ADD_LIQUIDITY_OFFSET);
    }

    function shouldCallAfterAddLiquidity(HooksConfigBits memory config) internal pure returns (bool) {
        return config.bits.decodeBool(AFTER_ADD_LIQUIDITY_OFFSET);
    }

    function setShouldCallAfterAddLiquidity(HooksConfigBits memory config, bool value) internal pure {
        config.bits = config.bits.insertBool(value, AFTER_ADD_LIQUIDITY_OFFSET);
    }

    function shouldCallBeforeRemoveLiquidity(HooksConfigBits memory config) internal pure returns (bool) {
        return config.bits.decodeBool(BEFORE_REMOVE_LIQUIDITY_OFFSET);
    }

    function setShouldCallBeforeRemoveLiquidity(HooksConfigBits memory config, bool value) internal pure {
        config.bits = config.bits.insertBool(value, BEFORE_REMOVE_LIQUIDITY_OFFSET);
    }

    function shouldCallAfterRemoveLiquidity(HooksConfigBits memory config) internal pure returns (bool) {
        return config.bits.decodeBool(AFTER_REMOVE_LIQUIDITY_OFFSET);
    }

    function setShouldCallAfterRemoveLiquidity(HooksConfigBits memory config, bool value) internal pure {
        config.bits = config.bits.insertBool(value, AFTER_REMOVE_LIQUIDITY_OFFSET);
    }

    function getHooksContract(HooksConfigBits memory config) internal pure returns (address) {
        return config.bits.decodeAddress(HOOKS_CONTRACT_OFFSET);
    }

    function setHooksContract(HooksConfigBits memory config, address value) internal pure {
        config.bits = config.bits.insertAddress(value, HOOKS_CONTRACT_OFFSET);
    }

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
        HooksConfigBits memory config,
        IBasePool.PoolSwapParams memory swapParams,
        uint256 staticSwapFeePercentage
    ) internal view returns (bool, uint256) {
        if (config.shouldCallComputeDynamicSwapFee() == false) {
            return (false, 0);
        }

        (bool success, uint256 swapFeePercentage) = IHooks(config.getHooksContract()).onComputeDynamicSwapFee(
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
     * @return success false if hook is disabled, true if hooks is enabled and succeeded to execute
     */
    function onBeforeSwap(
        HooksConfigBits memory config,
        IBasePool.PoolSwapParams memory swapParams
    ) internal returns (bool) {
        if (config.shouldCallBeforeSwap() == false) {
            return false;
        }

        if (IHooks(config.getHooksContract()).onBeforeSwap(swapParams) == false) {
            revert IVaultErrors.BeforeSwapHookFailed();
        }
        return true;
    }

    /**
     * @dev Check if after swap hook should be called and call it. Throws an error if the hook contract fails to
     * execute the hook.
     *
     * @param config The encoded hooks configuration
     * @param amountCalculatedScaled18 The amount calculated by the vault's onSwap function
     * @param params The swap parameters
     * @param state Temporary state used in swap operations
     * @param poolData Struct containing balance and token information of the pool
     */
    function onAfterSwap(
        HooksConfigBits memory config,
        uint256 amountCalculatedScaled18,
        address router,
        SwapParams memory params,
        SwapState memory state,
        PoolData memory poolData
    ) internal {
        if (config.shouldCallAfterSwap() == false) {
            return;
        }

        // Adjust balances for the AfterSwap hook.
        (uint256 amountInScaled18, uint256 amountOutScaled18) = params.kind == SwapKind.EXACT_IN
            ? (state.amountGivenScaled18, amountCalculatedScaled18)
            : (amountCalculatedScaled18, state.amountGivenScaled18);
        if (
            IHooks(config.getHooksContract()).onAfterSwap(
                IHooks.AfterSwapParams({
                    kind: params.kind,
                    tokenIn: params.tokenIn,
                    tokenOut: params.tokenOut,
                    amountInScaled18: amountInScaled18,
                    amountOutScaled18: amountOutScaled18,
                    tokenInBalanceScaled18: poolData.balancesLiveScaled18[state.indexIn],
                    tokenOutBalanceScaled18: poolData.balancesLiveScaled18[state.indexOut],
                    router: router,
                    userData: params.userData
                }),
                amountCalculatedScaled18
            ) == false
        ) {
            revert IVaultErrors.AfterSwapHookFailed();
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
        HooksConfigBits memory config,
        uint256[] memory maxAmountsInScaled18,
        address router,
        AddLiquidityParams memory params,
        PoolData memory poolData
    ) internal returns (bool) {
        if (config.shouldCallBeforeAddLiquidity() == false) {
            return false;
        }

        if (
            IHooks(config.getHooksContract()).onBeforeAddLiquidity(
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
     * @param amountsInScaled18 An array with amounts for each input token of the add liquidity operation
     * @param bptAmountOut The BPT amount a user will receive after add liquidity operation succeeds
     * @param params The add liquidity parameters
     * @param poolData Struct containing balance and token information of the pool
     */
    function onAfterAddLiquidity(
        HooksConfigBits memory config,
        uint256[] memory amountsInScaled18,
        uint256 bptAmountOut,
        address router,
        AddLiquidityParams memory params,
        PoolData memory poolData
    ) internal {
        if (config.shouldCallAfterAddLiquidity() == false) {
            return;
        }

        if (
            IHooks(config.getHooksContract()).onAfterAddLiquidity(
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
        HooksConfigBits memory config,
        uint256[] memory minAmountsOutScaled18,
        address router,
        RemoveLiquidityParams memory params,
        PoolData memory poolData
    ) internal returns (bool) {
        if (config.shouldCallBeforeRemoveLiquidity() == false) {
            return false;
        }

        if (
            IHooks(config.getHooksContract()).onBeforeRemoveLiquidity(
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
     * @param amountsOutScaled18 An array with amounts for each output token of the remove liquidity operation
     * @param bptAmountIn The BPT amount a user will need burn to remove the liquidity of the pool
     * @param params The remove liquidity parameters
     * @param poolData Struct containing balance and token information of the pool
     */
    function onAfterRemoveLiquidity(
        HooksConfigBits memory config,
        uint256[] memory amountsOutScaled18,
        uint256 bptAmountIn,
        address router,
        RemoveLiquidityParams memory params,
        PoolData memory poolData
    ) internal {
        if (config.shouldCallAfterRemoveLiquidity() == false) {
            return;
        }

        if (
            IHooks(config.getHooksContract()).onAfterRemoveLiquidity(
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
        HooksConfigBits memory config,
        uint256[] memory exactAmountsInScaled18,
        bytes memory userData
    ) internal returns (bool) {
        if (config.shouldCallBeforeInitialize() == false) {
            return false;
        }

        if (IHooks(config.getHooksContract()).onBeforeInitialize(exactAmountsInScaled18, userData) == false) {
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
        HooksConfigBits memory config,
        uint256[] memory exactAmountsInScaled18,
        uint256 bptAmountOut,
        bytes memory userData
    ) internal {
        if (config.shouldCallAfterInitialize() == false) {
            return;
        }

        if (
            IHooks(config.getHooksContract()).onAfterInitialize(exactAmountsInScaled18, bptAmountOut, userData) == false
        ) {
            revert IVaultErrors.AfterInitializeHookFailed();
        }
    }

    function toHooksConfig(HooksConfigBits memory config) internal pure returns (HooksConfig memory) {
        // Calling the functions (in addition to costing more gas), causes an obscure form of stack error (Yul errors).
        return
            HooksConfig({
                shouldCallBeforeInitialize: config.shouldCallBeforeInitialize(),
                shouldCallAfterInitialize: config.shouldCallAfterInitialize(),
                shouldCallBeforeAddLiquidity: config.shouldCallBeforeAddLiquidity(),
                shouldCallAfterAddLiquidity: config.shouldCallAfterAddLiquidity(),
                shouldCallBeforeRemoveLiquidity: config.shouldCallBeforeRemoveLiquidity(),
                shouldCallAfterRemoveLiquidity: config.shouldCallAfterRemoveLiquidity(),
                shouldCallComputeDynamicSwapFee: config.shouldCallComputeDynamicSwapFee(),
                shouldCallBeforeSwap: config.shouldCallBeforeSwap(),
                shouldCallAfterSwap: config.shouldCallAfterSwap(),
                hooksContract: config.getHooksContract()
            });
    }
}
