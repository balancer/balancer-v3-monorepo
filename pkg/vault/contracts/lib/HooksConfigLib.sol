// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { WordCodec } from "@balancer-labs/v3-solidity-utils/contracts/helpers/WordCodec.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

// @notice Config type to store entire configuration of the pool
type HooksConfigBits is bytes32;

using HooksConfigLib for HooksConfigBits global;

library HooksConfigLib {
    using WordCodec for bytes32;

    // Bit offsets for pool config
    uint8 public constant DYNAMIC_SWAP_FEE_OFFSET = 0;
    uint8 public constant BEFORE_SWAP_OFFSET = DYNAMIC_SWAP_FEE_OFFSET + 1;
    uint8 public constant AFTER_SWAP_OFFSET = BEFORE_SWAP_OFFSET + 1;
    uint8 public constant BEFORE_ADD_LIQUIDITY_OFFSET = AFTER_SWAP_OFFSET + 1;
    uint8 public constant AFTER_ADD_LIQUIDITY_OFFSET = BEFORE_ADD_LIQUIDITY_OFFSET + 1;
    uint8 public constant BEFORE_REMOVE_LIQUIDITY_OFFSET = AFTER_ADD_LIQUIDITY_OFFSET + 1;
    uint8 public constant AFTER_REMOVE_LIQUIDITY_OFFSET = BEFORE_REMOVE_LIQUIDITY_OFFSET + 1;
    uint8 public constant BEFORE_INITIALIZE_OFFSET = AFTER_REMOVE_LIQUIDITY_OFFSET + 1;
    uint8 public constant AFTER_INITIALIZE_OFFSET = BEFORE_INITIALIZE_OFFSET + 1;
    uint8 public constant HOOKS_CONTRACT_OFFSET = AFTER_INITIALIZE_OFFSET + 1;

    function shouldCallComputeDynamicSwapFee(HooksConfigBits config) internal pure returns (bool) {
        return HooksConfigBits.unwrap(config).decodeBool(DYNAMIC_SWAP_FEE_OFFSET);
    }

    function shouldCallBeforeSwap(HooksConfigBits config) internal pure returns (bool) {
        return HooksConfigBits.unwrap(config).decodeBool(BEFORE_SWAP_OFFSET);
    }

    function shouldCallAfterSwap(HooksConfigBits config) internal pure returns (bool) {
        return HooksConfigBits.unwrap(config).decodeBool(AFTER_SWAP_OFFSET);
    }

    function shouldCallBeforeAddLiquidity(HooksConfigBits config) internal pure returns (bool) {
        return HooksConfigBits.unwrap(config).decodeBool(BEFORE_ADD_LIQUIDITY_OFFSET);
    }

    function shouldCallAfterAddLiquidity(HooksConfigBits config) internal pure returns (bool) {
        return HooksConfigBits.unwrap(config).decodeBool(AFTER_ADD_LIQUIDITY_OFFSET);
    }

    function shouldCallBeforeRemoveLiquidity(HooksConfigBits config) internal pure returns (bool) {
        return HooksConfigBits.unwrap(config).decodeBool(BEFORE_REMOVE_LIQUIDITY_OFFSET);
    }

    function shouldCallAfterRemoveLiquidity(HooksConfigBits config) internal pure returns (bool) {
        return HooksConfigBits.unwrap(config).decodeBool(AFTER_REMOVE_LIQUIDITY_OFFSET);
    }

    function shouldCallBeforeInitialize(HooksConfigBits config) internal pure returns (bool) {
        return HooksConfigBits.unwrap(config).decodeBool(BEFORE_INITIALIZE_OFFSET);
    }

    function shouldCallAfterInitialize(HooksConfigBits config) internal pure returns (bool) {
        return HooksConfigBits.unwrap(config).decodeBool(AFTER_INITIALIZE_OFFSET);
    }

    /**
     * @dev returns false if hook is disabled, true if hooks is enabled and succeeded to execute, or throws
     * BeforeSwapHookFailed if the hook has failed
     */
    // TODO document
    function onBeforeSwap(
        HooksConfig memory config,
        IBasePool.PoolSwapParams memory swapParams
    ) internal returns (bool) {
        if (config.shouldCallBeforeSwap == false) {
            return false;
        }

        if (IHooks(config.hooksContract).onBeforeSwap(swapParams) == false) {
            revert IVaultErrors.BeforeSwapHookFailed();
        }
        return true;
    }

    // TODO document
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

    // TODO document
    function onAfterSwap(
        HooksConfig memory config,
        uint256 amountCalculatedScaled18,
        SwapParams memory params,
        SwapState memory state,
        PoolData memory poolData
    ) internal {
        if (config.shouldCallAfterSwap == false) {
            return;
        }

        // Adjust balances for the AfterSwap hook.
        (uint256 amountInScaled18, uint256 amountOutScaled18) = params.kind == SwapKind.EXACT_IN
            ? (state.amountGivenScaled18, amountCalculatedScaled18)
            : (amountCalculatedScaled18, state.amountGivenScaled18);
        if (
            IHooks(config.hooksContract).onAfterSwap(
                IHooks.AfterSwapParams({
                    kind: params.kind,
                    tokenIn: params.tokenIn,
                    tokenOut: params.tokenOut,
                    amountInScaled18: amountInScaled18,
                    amountOutScaled18: amountOutScaled18,
                    tokenInBalanceScaled18: poolData.balancesLiveScaled18[state.indexIn],
                    tokenOutBalanceScaled18: poolData.balancesLiveScaled18[state.indexOut],
                    router: msg.sender,
                    userData: params.userData
                }),
                amountCalculatedScaled18
            ) == false
        ) {
            revert IVaultErrors.AfterSwapHookFailed();
        }
    }

    // TODO document
    function onBeforeAddLiquidity(
        HooksConfig memory config,
        uint256[] memory maxAmountsInScaled18,
        AddLiquidityParams memory params,
        PoolData memory poolData
    ) internal returns (bool) {
        if (config.shouldCallBeforeAddLiquidity == false) {
            return false;
        }

        if (
            IHooks(config.hooksContract).onBeforeAddLiquidity(
                msg.sender,
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

    // TODO document
    function onAfterAddLiquidity(
        HooksConfig memory config,
        uint256[] memory amountsInScaled18,
        uint256 bptAmountOut,
        AddLiquidityParams memory params,
        PoolData memory poolData
    ) internal {
        if (config.shouldCallAfterAddLiquidity == false) {
            return;
        }

        if (
            IHooks(config.hooksContract).onAfterAddLiquidity(
                msg.sender,
                amountsInScaled18,
                bptAmountOut,
                poolData.balancesLiveScaled18,
                params.userData
            ) == false
        ) {
            revert IVaultErrors.AfterAddLiquidityHookFailed();
        }
    }

    // TODO document
    function onBeforeRemoveLiquidity(
        HooksConfig memory config,
        uint256[] memory minAmountsOutScaled18,
        RemoveLiquidityParams memory params,
        PoolData memory poolData
    ) internal returns (bool) {
        if (config.shouldCallBeforeRemoveLiquidity == false) {
            return false;
        }

        if (
            IHooks(config.hooksContract).onBeforeRemoveLiquidity(
                msg.sender,
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

    // TODO document
    function onAfterRemoveLiquidity(
        HooksConfig memory config,
        uint256[] memory amountsOutScaled18,
        uint256 bptAmountIn,
        RemoveLiquidityParams memory params,
        PoolData memory poolData
    ) internal {
        if (config.shouldCallAfterRemoveLiquidity == false) {
            return;
        }

        if (
            IHooks(config.hooksContract).onAfterRemoveLiquidity(
                msg.sender,
                bptAmountIn,
                amountsOutScaled18,
                poolData.balancesLiveScaled18,
                params.userData
            ) == false
        ) {
            revert IVaultErrors.AfterRemoveLiquidityHookFailed();
        }
    }

    // TODO document
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

    function getHooksContract(HooksConfigBits config) internal pure returns (address) {
        return HooksConfigBits.unwrap(config).decodeAddress(HOOKS_CONTRACT_OFFSET);
    }

    function fromHooksConfig(HooksConfig memory config) internal pure returns (HooksConfigBits) {
        bytes32 configBits = bytes32(0);

        // Stack too deep.
        {
            configBits = configBits
                .insertBool(config.shouldCallBeforeSwap, BEFORE_SWAP_OFFSET)
                .insertBool(config.shouldCallAfterSwap, AFTER_SWAP_OFFSET)
                .insertAddress(config.hooksContract, HOOKS_CONTRACT_OFFSET);
        }

        {
            configBits = configBits
                .insertBool(config.shouldCallBeforeAddLiquidity, BEFORE_ADD_LIQUIDITY_OFFSET)
                .insertBool(config.shouldCallAfterAddLiquidity, AFTER_ADD_LIQUIDITY_OFFSET)
                .insertBool(config.shouldCallBeforeRemoveLiquidity, BEFORE_REMOVE_LIQUIDITY_OFFSET)
                .insertBool(config.shouldCallAfterRemoveLiquidity, AFTER_REMOVE_LIQUIDITY_OFFSET);
        }

        {
            configBits = configBits
                .insertBool(config.shouldCallBeforeInitialize, BEFORE_INITIALIZE_OFFSET)
                .insertBool(config.shouldCallAfterInitialize, AFTER_INITIALIZE_OFFSET)
                .insertBool(config.shouldCallComputeDynamicSwapFee, DYNAMIC_SWAP_FEE_OFFSET);
        }

        return HooksConfigBits.wrap(configBits);
    }

    function toHooksConfig(HooksConfigBits config) internal pure returns (HooksConfig memory) {
        bytes32 rawConfig = HooksConfigBits.unwrap(config);

        // Calling the functions (in addition to costing more gas), causes an obscure form of stack error (Yul errors).
        return
            HooksConfig({
                shouldCallBeforeInitialize: rawConfig.decodeBool(BEFORE_INITIALIZE_OFFSET),
                shouldCallAfterInitialize: rawConfig.decodeBool(AFTER_INITIALIZE_OFFSET),
                shouldCallBeforeAddLiquidity: rawConfig.decodeBool(BEFORE_ADD_LIQUIDITY_OFFSET),
                shouldCallAfterAddLiquidity: rawConfig.decodeBool(AFTER_ADD_LIQUIDITY_OFFSET),
                shouldCallBeforeRemoveLiquidity: rawConfig.decodeBool(BEFORE_REMOVE_LIQUIDITY_OFFSET),
                shouldCallAfterRemoveLiquidity: rawConfig.decodeBool(AFTER_REMOVE_LIQUIDITY_OFFSET),
                shouldCallComputeDynamicSwapFee: rawConfig.decodeBool(DYNAMIC_SWAP_FEE_OFFSET),
                shouldCallBeforeSwap: rawConfig.decodeBool(BEFORE_SWAP_OFFSET),
                shouldCallAfterSwap: rawConfig.decodeBool(AFTER_SWAP_OFFSET),
                hooksContract: rawConfig.decodeAddress(HOOKS_CONTRACT_OFFSET)
            });
    }
}
