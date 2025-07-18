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

struct Context {
    IAggregatorRouter aggregatorRouter;
    IAggregatorBatchRouter aggregatorBatchRouter;
    IVault vault;
}

library BalancerLib {
    using SafeERC20 for IERC20;
    using BalancerInternalLib for Context;

    //TODO: maybe we can use the Registry or specific Registry for library
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
            BalancerInternalLib._swapSingleTokenExactIn(
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
            BalancerInternalLib._swapSingleTokenExactIn(
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
        IERC20 wrapedTokenIn,
        IERC20 unwrapedTokenOut
    ) internal returns (uint256 amountOut) {
        return
            BalancerInternalLib._swapSingleTokenExactIn(
                context,
                pool,
                tokenIn,
                tokenOut,
                exactAmountIn,
                minAmountOut,
                deadline,
                wrapedTokenIn,
                unwrapedTokenOut,
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
        IERC20 wrapedTokenIn,
        IERC20 unwrapedTokenOut,
        bytes memory userData
    ) internal returns (uint256 amountOut) {
        return
            BalancerInternalLib._swapSingleTokenExactIn(
                context,
                pool,
                tokenIn,
                tokenOut,
                exactAmountIn,
                minAmountOut,
                deadline,
                wrapedTokenIn,
                unwrapedTokenOut,
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
            BalancerInternalLib._swapSingleTokenExactOut(
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
            BalancerInternalLib._swapSingleTokenExactOut(
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
        IERC20 wrapedTokenIn,
        IERC20 unwrapedTokenOut
    ) internal returns (uint256 amountIn) {
        return
            BalancerInternalLib._swapSingleTokenExactOut(
                context,
                pool,
                tokenIn,
                tokenOut,
                exactAmountOut,
                maxAmountIn,
                deadline,
                wrapedTokenIn,
                unwrapedTokenOut,
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
        IERC20 wrapedTokenIn,
        IERC20 unwrapedTokenOut,
        bytes memory userData
    ) internal returns (uint256 amountIn) {
        return
            BalancerInternalLib._swapSingleTokenExactOut(
                context,
                pool,
                tokenIn,
                tokenOut,
                exactAmountOut,
                maxAmountIn,
                deadline,
                wrapedTokenIn,
                unwrapedTokenOut,
                userData
            );
    }
}

library BalancerInternalLib {
    using SafeERC20 for IERC20;

    function _swapSingleTokenExactIn(
        Context memory context,
        address pool,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 exactAmountIn,
        uint256 minAmountOut,
        uint256 deadline,
        bytes memory userData
    ) internal returns (uint256 amountOut) {
        tokenIn.safeTransfer(address(context.vault), exactAmountIn);

        amountOut = context.aggregatorRouter.swapSingleTokenExactIn(
            pool,
            tokenIn,
            tokenOut,
            exactAmountIn,
            minAmountOut,
            deadline,
            userData
        );
    }

    function _swapSingleTokenExactIn(
        Context memory context,
        address pool,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 exactAmountIn,
        uint256 minAmountOut,
        uint256 deadline,
        IERC20 wrapedTokenIn,
        IERC20 unwrapedTokenOut,
        bytes memory userData
    ) internal returns (uint256 amountOut) {
        tokenIn.safeTransfer(address(context.vault), exactAmountIn);

        IBatchRouter.SwapPathExactAmountIn[] memory paths = new IBatchRouter.SwapPathExactAmountIn[](1);
        paths[0] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: tokenIn,
            steps: _makeSwapPathSteps(pool, tokenIn, tokenOut, wrapedTokenIn, unwrapedTokenOut),
            exactAmountIn: exactAmountIn,
            minAmountOut: minAmountOut
        });

        (uint256[] memory pathAmountsOut, , ) = context.aggregatorBatchRouter.swapExactIn(paths, deadline, userData);

        return pathAmountsOut[0];
    }

    function _swapSingleTokenExactOut(
        Context memory context,
        address pool,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 exactAmountOut,
        uint256 maxAmountIn,
        uint256 deadline,
        bytes memory userData
    ) internal returns (uint256 amountIn) {
        tokenIn.safeTransfer(address(context.vault), maxAmountIn);

        amountIn = context.aggregatorRouter.swapSingleTokenExactOut(
            pool,
            tokenIn,
            tokenOut,
            exactAmountOut,
            maxAmountIn,
            deadline,
            userData
        );
    }

    function _swapSingleTokenExactOut(
        Context memory context,
        address pool,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 exactAmountOut,
        uint256 maxAmountIn,
        uint256 deadline,
        IERC20 wrapedTokenIn,
        IERC20 unwrapedTokenOut,
        bytes memory userData
    ) internal returns (uint256 amountIn) {
        tokenIn.safeTransfer(address(context.vault), maxAmountIn);

        IBatchRouter.SwapPathExactAmountOut[] memory paths = new IBatchRouter.SwapPathExactAmountOut[](1);
        paths[0] = IBatchRouter.SwapPathExactAmountOut({
            tokenIn: tokenIn,
            steps: _makeSwapPathSteps(pool, tokenIn, tokenOut, wrapedTokenIn, unwrapedTokenOut),
            exactAmountOut: exactAmountOut,
            maxAmountIn: maxAmountIn
        });

        (uint256[] memory pathAmountsOut, , ) = context.aggregatorBatchRouter.swapExactOut(paths, deadline, userData);

        return pathAmountsOut[0];
    }

    function _makeSwapPathSteps(
        address pool,
        IERC20 tokenIn,
        IERC20 tokenOut,
        IERC20 wrapedTokenIn,
        IERC20 unwrapedTokenOut
    ) private pure returns (IBatchRouter.SwapPathStep[] memory steps) {
        IBatchRouter.SwapPathStep memory wrapPath;
        IBatchRouter.SwapPathStep memory swapPath;
        IBatchRouter.SwapPathStep memory unwrapPath;

        bool wrapTokenIn = wrapedTokenIn != IERC20(address(0));
        bool unwrapTokenOut = unwrapedTokenOut != IERC20(address(0));

        IERC20 finalTokenOut = unwrapTokenOut ? unwrapedTokenOut : tokenOut;
        if (wrapTokenIn) {
            wrapPath = IBatchRouter.SwapPathStep({ pool: address(wrapedTokenIn), tokenOut: tokenIn, isBuffer: true });
        }

        if (unwrapTokenOut) {
            unwrapPath = IBatchRouter.SwapPathStep({
                pool: address(tokenOut),
                tokenOut: unwrapedTokenOut,
                isBuffer: true
            });
        }

        swapPath = IBatchRouter.SwapPathStep({ pool: pool, tokenOut: finalTokenOut, isBuffer: false });

        uint256 stepLength = 1 + (wrapTokenIn ? 1 : 0) + (unwrapTokenOut ? 1 : 0);
        steps = new IBatchRouter.SwapPathStep[](stepLength);

        for (uint256 i = 0; i < stepLength; i++) {
            if (i == 0 && wrapTokenIn) {
                steps[i] = wrapPath;
            } else if (i <= 1) {
                steps[i] = swapPath;
            } else {
                steps[i] = unwrapPath;
            }
        }
    }
}
