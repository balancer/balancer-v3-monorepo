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

library BalancerInternalLib {
    using SafeERC20 for IERC20;

    function swapSingleTokenExactIn(
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
        // Determine the actual tokenIn to be used for the swap.
        // If the underlying token is specified, we need to wrap it first,
        // so the swap is performed using the corresponding wrapped token.
        // Otherwise, the provided tokenIn is used directly.
        IERC20 effectiveTokenIn = useUnderlyingTokenIn ? IERC20(IERC4626(address(tokenIn)).asset()) : tokenIn;

        // Transfer the exact amount in to the vault.
        effectiveTokenIn.safeTransfer(address(context.vault), exactAmountIn);

        IBatchRouter.SwapPathExactAmountIn[] memory paths = new IBatchRouter.SwapPathExactAmountIn[](1);
        paths[0] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: effectiveTokenIn,
            steps: _makeSwapPathSteps(pool, tokenIn, tokenOut, useUnderlyingTokenIn, useUnderlyingTokenOut),
            exactAmountIn: exactAmountIn,
            minAmountOut: minAmountOut
        });

        (uint256[] memory pathAmountsOut, , ) = context.aggregatorBatchRouter.swapExactIn(paths, deadline, userData);

        return pathAmountsOut[0];
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
        IBatchRouter.SwapPathExactAmountOut[] memory paths = new IBatchRouter.SwapPathExactAmountOut[](1);
        paths[0] = IBatchRouter.SwapPathExactAmountOut({
            tokenIn: tokenIn,
            steps: _makeSwapPathSteps(pool, tokenIn, tokenOut, useUnderlyingTokenIn, useUnderlyingTokenOut),
            exactAmountOut: exactAmountOut,
            maxAmountIn: maxAmountIn
        });

        (uint256[] memory pathAmountsOut, , ) = context.aggregatorBatchRouter.swapExactOut(paths, deadline, userData);

        return pathAmountsOut[0];
    }

    function _makeSwapPathSteps(
        address pool,
        IERC20 poolTokenIn,
        IERC20 poolTokenOut,
        bool useUnderlyingTokenIn,
        bool useUnderlyingTokenOut
    ) private view returns (IBatchRouter.SwapPathStep[] memory steps) {
        IBatchRouter.SwapPathStep memory wrapPath;
        IBatchRouter.SwapPathStep memory swapPath;
        IBatchRouter.SwapPathStep memory unwrapPath;

        if (useUnderlyingTokenIn) {
            wrapPath = IBatchRouter.SwapPathStep({ pool: address(poolTokenIn), tokenOut: poolTokenIn, isBuffer: true });
        }

        swapPath = IBatchRouter.SwapPathStep({ pool: pool, tokenOut: poolTokenOut, isBuffer: false });

        if (useUnderlyingTokenOut) {
            unwrapPath = IBatchRouter.SwapPathStep({
                pool: address(IERC4626(address(poolTokenOut)).asset()),
                tokenOut: poolTokenOut,
                isBuffer: true
            });
        }

        uint256 stepLength = 1 + (useUnderlyingTokenIn ? 1 : 0) + (useUnderlyingTokenOut ? 1 : 0);
        steps = new IBatchRouter.SwapPathStep[](stepLength);

        // Fill the steps array based on whether wrapping or unwrapping is needed
        {
            uint256 i = 0;
            if (useUnderlyingTokenIn) {
                steps[i] = wrapPath;
                unchecked {
                    i++;
                }
            }

            steps[i] = swapPath;
            unchecked {
                i++;
            }

            if (useUnderlyingTokenOut) {
                steps[i] = unwrapPath;
            }
        }
    }
}
