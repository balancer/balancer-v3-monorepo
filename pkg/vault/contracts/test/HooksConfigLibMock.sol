// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { HooksConfigLib } from "../lib/HooksConfigLib.sol";

contract HooksConfigLibMock {
    using HooksConfigLib for PoolConfigBits;

    function callComputeDynamicSwapFeeHook(
        PoolSwapParams memory swapParams,
        address pool,
        uint256 staticSwapFeePercentage,
        IHooks hooksContract
    ) public view returns (uint256) {
        return HooksConfigLib.callComputeDynamicSwapFeeHook(swapParams, pool, staticSwapFeePercentage, hooksContract);
    }

    function callBeforeSwapHook(PoolSwapParams memory swapParams, address pool, IHooks hooksContract) public {
        HooksConfigLib.callBeforeSwapHook(swapParams, pool, hooksContract);
    }

    function callAfterSwapHook(
        PoolConfigBits config,
        uint256 amountCalculatedScaled18,
        uint256 amountCalculatedRaw,
        address router,
        SwapParams memory params,
        SwapState memory state,
        PoolData memory poolData,
        IHooks hooksContract
    ) public returns (uint256) {
        return
            HooksConfigLib.callAfterSwapHook(
                config,
                amountCalculatedScaled18,
                amountCalculatedRaw,
                router,
                params,
                state,
                poolData,
                hooksContract
            );
    }

    function callBeforeAddLiquidityHook(
        address router,
        uint256[] memory maxAmountsInScaled18,
        AddLiquidityParams memory params,
        PoolData memory poolData,
        IHooks hooksContract
    ) public {
        HooksConfigLib.callBeforeAddLiquidityHook(router, maxAmountsInScaled18, params, poolData, hooksContract);
    }

    function callAfterAddLiquidityHook(
        PoolConfigBits config,
        address router,
        uint256[] memory amountsInScaled18,
        uint256[] memory amountsInRaw,
        uint256 bptAmountOut,
        AddLiquidityParams memory params,
        PoolData memory poolData,
        IHooks hooksContract
    ) public returns (uint256[] memory) {
        return
            HooksConfigLib.callAfterAddLiquidityHook(
                config,
                router,
                amountsInScaled18,
                amountsInRaw,
                bptAmountOut,
                params,
                poolData,
                hooksContract
            );
    }

    function callBeforeRemoveLiquidityHook(
        uint256[] memory minAmountsOutScaled18,
        address router,
        RemoveLiquidityParams memory params,
        PoolData memory poolData,
        IHooks hooksContract
    ) public {
        HooksConfigLib.callBeforeRemoveLiquidityHook(minAmountsOutScaled18, router, params, poolData, hooksContract);
    }

    function callAfterRemoveLiquidityHook(
        PoolConfigBits config,
        address router,
        uint256[] memory amountsOutScaled18,
        uint256[] memory amountsOutRaw,
        uint256 bptAmountIn,
        RemoveLiquidityParams memory params,
        PoolData memory poolData,
        IHooks hooksContract
    ) public returns (uint256[] memory) {
        return
            HooksConfigLib.callAfterRemoveLiquidityHook(
                config,
                router,
                amountsOutScaled18,
                amountsOutRaw,
                bptAmountIn,
                params,
                poolData,
                hooksContract
            );
    }

    function callBeforeInitializeHook(
        uint256[] memory exactAmountsInScaled18,
        bytes memory userData,
        IHooks hooksContract
    ) public {
        HooksConfigLib.callBeforeInitializeHook(exactAmountsInScaled18, userData, hooksContract);
    }

    function callAfterInitializeHook(
        uint256[] memory amountsInScaled18,
        uint256 bptAmountOut,
        bytes memory userData,
        IHooks hooksContract
    ) public {
        HooksConfigLib.callAfterInitializeHook(amountsInScaled18, bptAmountOut, userData, hooksContract);
    }
}
