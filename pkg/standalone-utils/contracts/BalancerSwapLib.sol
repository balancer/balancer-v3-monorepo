// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IAggregatorBatchRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IAggregatorBatchRouter.sol";
import { IAggregatorRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IAggregatorRouter.sol";
import { IRouterCommon } from "@balancer-labs/v3-interfaces/contracts/vault/IRouterCommon.sol";
import { IBatchRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IBatchRouter.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { BalancerContext, BalancerPureLib } from "./BalancerPureLib.sol";

library BalancerSwapLib {
    using SafeERC20 for IERC20;

    struct CommonParams {
        BalancerContext context;
        address pool;
        IERC20 poolTokenIn;
        IERC20 poolTokenOut;
        uint256 deadline;
        bool wrapTokenIn;
        bool unwrapTokenOut;
        bytes userData;
    }

    struct SwapExactInParams {
        CommonParams common;
        uint256 exactAmountIn;
        uint256 minAmountOut;
    }

    struct SwapExactOutParams {
        CommonParams common;
        uint256 exactAmountOut;
        uint256 maxAmountIn;
    }

    function createContext(
        address aggregatorRouter,
        address aggregatorBatchRouter
    ) internal view returns (BalancerContext memory) {
        return BalancerPureLib.createContext(aggregatorRouter, aggregatorBatchRouter);
    }

    /***************************************************************************
                                   Swap Exact In
    ***************************************************************************/

    function buildSwapExactIn(
        BalancerContext memory ctx,
        address pool,
        IERC20 poolTokenIn,
        IERC20 poolTokenOut,
        uint256 exactAmountIn,
        uint256 minAmountOut,
        uint256 deadline
    ) internal pure returns (SwapExactInParams memory) {
        return
            SwapExactInParams({
                common: CommonParams({
                    context: ctx,
                    pool: pool,
                    poolTokenIn: poolTokenIn,
                    poolTokenOut: poolTokenOut,
                    deadline: deadline,
                    wrapTokenIn: false,
                    unwrapTokenOut: false,
                    userData: bytes("")
                }),
                exactAmountIn: exactAmountIn,
                minAmountOut: minAmountOut
            });
    }

    function wrapTokenIn(SwapExactInParams memory params) internal pure returns (SwapExactInParams memory) {
        params.common.wrapTokenIn = true;
        return params;
    }

    function unwrapTokenOut(SwapExactInParams memory params) internal pure returns (SwapExactInParams memory) {
        params.common.unwrapTokenOut = true;
        return params;
    }

    function withUserData(
        SwapExactInParams memory params,
        bytes memory userData
    ) internal pure returns (SwapExactInParams memory) {
        params.common.userData = userData;
        return params;
    }

    function execute(SwapExactInParams memory params) internal returns (uint256 amountOut) {
        if (params.common.wrapTokenIn == false && params.common.unwrapTokenOut == false) {
            return
                BalancerPureLib.swapSingleTokenExactIn(
                    params.common.context,
                    params.common.pool,
                    params.common.poolTokenIn,
                    params.common.poolTokenOut,
                    params.exactAmountIn,
                    params.minAmountOut,
                    params.common.deadline,
                    params.common.userData
                );
        }

        return
            BalancerPureLib.batchSwapSingleTokenExactIn(
                params.common.context,
                params.common.pool,
                params.common.poolTokenIn,
                params.common.poolTokenOut,
                params.exactAmountIn,
                params.minAmountOut,
                params.common.deadline,
                params.common.wrapTokenIn,
                params.common.unwrapTokenOut,
                params.common.userData
            );
    }

    function query(SwapExactInParams memory params, address sender) internal returns (uint256 amountOut) {
        return
            BalancerPureLib.querySwapSingleTokenExactIn(
                params.common.context,
                params.common.pool,
                params.common.poolTokenIn,
                params.common.poolTokenOut,
                params.exactAmountIn,
                params.minAmountOut,
                params.common.wrapTokenIn,
                params.common.unwrapTokenOut,
                sender,
                params.common.userData
            );
    }

    /***************************************************************************
                                   Swap Exact Out
    ***************************************************************************/

    function buildSwapExactOut(
        BalancerContext memory ctx,
        address pool,
        IERC20 poolTokenIn,
        IERC20 poolTokenOut,
        uint256 exactAmountOut,
        uint256 maxAmountIn,
        uint256 deadline
    ) internal pure returns (SwapExactOutParams memory) {
        return
            SwapExactOutParams({
                common: CommonParams({
                    context: ctx,
                    pool: pool,
                    poolTokenIn: poolTokenIn,
                    poolTokenOut: poolTokenOut,
                    deadline: deadline,
                    wrapTokenIn: false,
                    unwrapTokenOut: false,
                    userData: bytes("")
                }),
                exactAmountOut: exactAmountOut,
                maxAmountIn: maxAmountIn
            });
    }

    function wrapTokenIn(SwapExactOutParams memory params) internal pure returns (SwapExactOutParams memory) {
        params.common.wrapTokenIn = true;
        return params;
    }

    function unwrapTokenOut(SwapExactOutParams memory params) internal pure returns (SwapExactOutParams memory) {
        params.common.unwrapTokenOut = true;
        return params;
    }

    function withUserData(
        SwapExactOutParams memory params,
        bytes memory userData
    ) internal pure returns (SwapExactOutParams memory) {
        params.common.userData = userData;
        return params;
    }

    function execute(SwapExactOutParams memory params) internal returns (uint256 amountIn) {
        if (params.common.wrapTokenIn == false && params.common.unwrapTokenOut == false) {
            return
                BalancerPureLib.swapSingleTokenExactOut(
                    params.common.context,
                    params.common.pool,
                    params.common.poolTokenIn,
                    params.common.poolTokenOut,
                    params.exactAmountOut,
                    params.maxAmountIn,
                    params.common.deadline,
                    params.common.userData
                );
        }

        return
            BalancerPureLib.batchSwapSingleTokenExactOut(
                params.common.context,
                params.common.pool,
                params.common.poolTokenIn,
                params.common.poolTokenOut,
                params.exactAmountOut,
                params.maxAmountIn,
                params.common.deadline,
                params.common.wrapTokenIn,
                params.common.unwrapTokenOut,
                params.common.userData
            );
    }

    function query(SwapExactOutParams memory params, address sender) internal returns (uint256 amountIn) {
        return
            BalancerPureLib.querySwapSingleTokenExactOut(
                params.common.context,
                params.common.pool,
                params.common.poolTokenIn,
                params.common.poolTokenOut,
                params.exactAmountOut,
                params.maxAmountIn,
                params.common.wrapTokenIn,
                params.common.unwrapTokenOut,
                sender,
                params.common.userData
            );
    }
}
