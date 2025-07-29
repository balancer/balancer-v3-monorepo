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

import { Context, BalancerInternalLib } from "./BalancerInternalLib.sol";

library BalancerSwapLib {
    using SafeERC20 for IERC20;

    struct CommonParams {
        Context context;
        address pool;
        IERC20 tokenIn;
        IERC20 tokenOut;
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
    ) internal view returns (Context memory) {
        return
            Context({
                aggregatorRouter: IAggregatorRouter(aggregatorRouter),
                aggregatorBatchRouter: IAggregatorBatchRouter(aggregatorBatchRouter),
                vault: IRouterCommon(aggregatorRouter).getVault()
            });
    }

    /***************************************************************************
                                   Swap Exact In
    ***************************************************************************/

    function buildSwapExactIn(
        Context memory ctx,
        address pool,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 exactAmountIn,
        uint256 minAmountOut,
        uint256 deadline
    ) internal pure returns (SwapExactInParams memory) {
        return
            SwapExactInParams({
                common: CommonParams({
                    context: ctx,
                    pool: pool,
                    tokenIn: tokenIn,
                    tokenOut: tokenOut,
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

    function execute(SwapExactInParams memory params) internal returns (uint256 amountOut) {
        return
            BalancerInternalLib.swapSingleTokenExactIn(
                params.common.context,
                params.common.pool,
                params.common.tokenIn,
                params.common.tokenOut,
                params.exactAmountIn,
                params.minAmountOut,
                params.common.deadline,
                params.common.wrapTokenIn,
                params.common.unwrapTokenOut,
                params.common.userData
            );
    }

    /***************************************************************************
                                   Swap Exact In
    ***************************************************************************/

    function buildSwapExactOut(
        Context memory ctx,
        address pool,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 exactAmountOut,
        uint256 maxAmountIn,
        uint256 deadline
    ) internal pure returns (SwapExactOutParams memory) {
        return
            SwapExactOutParams({
                common: CommonParams({
                    context: ctx,
                    pool: pool,
                    tokenIn: tokenIn,
                    tokenOut: tokenOut,
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

    function execute(SwapExactOutParams memory params) internal returns (uint256 amountIn) {
        return
            BalancerInternalLib.swapSingleTokenExactOut(
                params.common.context,
                params.common.pool,
                params.common.tokenIn,
                params.common.tokenOut,
                params.exactAmountOut,
                params.maxAmountIn,
                params.common.deadline,
                params.common.wrapTokenIn,
                params.common.unwrapTokenOut,
                params.common.userData
            );
    }
}
