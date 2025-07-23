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
    using BalancerInternalLib for Context;

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

    function swapSingleTokenExactIn(
        Context memory context,
        address pool,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 exactAmountIn,
        uint256 minAmountOut,
        uint256 deadline
    ) internal returns (uint256 amountOut) {
        return
            BalancerInternalLib.swapSingleTokenExactIn(
                context,
                pool,
                tokenIn,
                tokenOut,
                exactAmountIn,
                minAmountOut,
                deadline,
                bytes("")
            );
    }

    function swapSingleTokenExactIn(
        Context memory context,
        address pool,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 exactAmountIn,
        uint256 minAmountOut,
        uint256 deadline,
        bytes memory userData
    ) internal returns (uint256) {
        return
            BalancerInternalLib.swapSingleTokenExactIn(
                context,
                pool,
                tokenIn,
                tokenOut,
                exactAmountIn,
                minAmountOut,
                deadline,
                userData
            );
    }

    function swapSingleTokenExactIn(
        Context memory context,
        address pool,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 exactAmountIn,
        uint256 minAmountOut,
        uint256 deadline,
        bool useUnderlyingTokenIn,
        bool useUnderlyingTokenOut
    ) internal returns (uint256 amountOut) {
        return
            BalancerInternalLib.swapSingleTokenExactIn(
                context,
                pool,
                tokenIn,
                tokenOut,
                exactAmountIn,
                minAmountOut,
                deadline,
                useUnderlyingTokenIn,
                useUnderlyingTokenOut,
                bytes("")
            );
    }

    function swapSingleTokenExactIn(
        Context memory context,
        address pool,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 exactAmountIn,
        uint256 minAmountOut,
        uint256 deadline,
        bool useUnderlyingTokenIn,
        bool useUnderlyingTokenOut,
        bytes memory userData
    ) internal returns (uint256 amountOut) {
        return
            BalancerInternalLib.swapSingleTokenExactIn(
                context,
                pool,
                tokenIn,
                tokenOut,
                exactAmountIn,
                minAmountOut,
                deadline,
                useUnderlyingTokenIn,
                useUnderlyingTokenOut,
                userData
            );
    }

    /***************************************************************************
                                   Swap Exact Out
    ***************************************************************************/

    function swapSingleTokenExactOut(
        Context memory context,
        address pool,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 exactAmountOut,
        uint256 maxAmountIn,
        uint256 deadline
    ) internal returns (uint256 amountIn) {
        return
            BalancerInternalLib.swapSingleTokenExactOut(
                context,
                pool,
                tokenIn,
                tokenOut,
                exactAmountOut,
                maxAmountIn,
                deadline,
                bytes("")
            );
    }

    function swapSingleTokenExactOut(
        Context memory context,
        address pool,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 exactAmountOut,
        uint256 maxAmountIn,
        uint256 deadline,
        bytes memory userData
    ) internal returns (uint256 amountIn) {
        return
            BalancerInternalLib.swapSingleTokenExactOut(
                context,
                pool,
                tokenIn,
                tokenOut,
                exactAmountOut,
                maxAmountIn,
                deadline,
                userData
            );
    }

    function swapSingleTokenExactOut(
        Context memory context,
        address pool,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 exactAmountOut,
        uint256 maxAmountIn,
        uint256 deadline,
        bool useUnderlyingTokenIn,
        bool useUnderlyingTokenOut
    ) internal returns (uint256 amountIn) {
        return
            BalancerInternalLib.swapSingleTokenExactOut(
                context,
                pool,
                tokenIn,
                tokenOut,
                exactAmountOut,
                maxAmountIn,
                deadline,
                useUnderlyingTokenIn,
                useUnderlyingTokenOut,
                bytes("")
            );
    }

    function swapSingleTokenExactOut(
        Context memory context,
        address pool,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 exactAmountOut,
        uint256 maxAmountIn,
        uint256 deadline,
        bool useUnderlyingTokenIn,
        bool useUnderlyingTokenOut,
        bytes memory userData
    ) internal returns (uint256 amountIn) {
        return
            BalancerInternalLib.swapSingleTokenExactOut(
                context,
                pool,
                tokenIn,
                tokenOut,
                exactAmountOut,
                maxAmountIn,
                deadline,
                useUnderlyingTokenIn,
                useUnderlyingTokenOut,
                userData
            );
    }
}
