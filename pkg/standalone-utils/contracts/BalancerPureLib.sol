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

struct BalancerContext {
    IAggregatorRouter aggregatorRouter;
    IAggregatorBatchRouter aggregatorBatchRouter;
    IVault vault;
}

library BalancerPureLib {
    using SafeERC20 for IERC20;

    function createContext(
        address aggregatorRouter,
        address aggregatorBatchRouter
    ) internal view returns (BalancerContext memory) {
        return
            BalancerContext({
                aggregatorRouter: IAggregatorRouter(aggregatorRouter),
                aggregatorBatchRouter: IAggregatorBatchRouter(aggregatorBatchRouter),
                vault: IRouterCommon(aggregatorRouter).getVault()
            });
    }

    function querySwapSingleTokenExactIn(
        BalancerContext memory context,
        address pool,
        IERC20 poolTokenIn,
        IERC20 poolTokenOut,
        uint256 exactAmountIn,
        uint256 minAmountOut,
        bool needToWrapTokenIn,
        bool needToUnwrapTokenOut,
        address sender,
        bytes memory userData
    ) internal returns (uint256 amountOut) {
        (IERC20 pathTokenIn, IBatchRouter.SwapPathStep[] memory steps) = _computePathTokenInAndSteps(
            context,
            pool,
            poolTokenIn,
            poolTokenOut,
            needToWrapTokenIn,
            needToUnwrapTokenOut
        );

        IBatchRouter.SwapPathExactAmountIn[] memory paths = new IBatchRouter.SwapPathExactAmountIn[](1);
        paths[0] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: pathTokenIn,
            steps: steps,
            exactAmountIn: exactAmountIn,
            minAmountOut: minAmountOut
        });

        (uint256[] memory pathAmountsOut, , ) = context.aggregatorBatchRouter.querySwapExactIn(paths, sender, userData);

        return pathAmountsOut[0];
    }

    function swapSingleTokenExactIn(
        BalancerContext memory context,
        address pool,
        IERC20 poolTokenIn,
        IERC20 poolTokenOut,
        uint256 exactAmountIn,
        uint256 minAmountOut,
        uint256 deadline,
        bytes memory userData
    ) internal returns (uint256 amountOut) {
        poolTokenIn.safeTransfer(address(context.vault), exactAmountIn);

        return
            context.aggregatorRouter.swapSingleTokenExactIn(
                pool,
                poolTokenIn,
                poolTokenOut,
                exactAmountIn,
                minAmountOut,
                deadline,
                userData
            );
    }

    function batchSwapSingleTokenExactIn(
        BalancerContext memory context,
        address pool,
        IERC20 poolTokenIn,
        IERC20 poolTokenOut,
        uint256 exactAmountIn,
        uint256 minAmountOut,
        uint256 deadline,
        bool needToWrapTokenIn,
        bool needToUnwrapTokenOut,
        bytes memory userData
    ) internal returns (uint256 amountOut) {
        (IERC20 pathTokenIn, IBatchRouter.SwapPathStep[] memory steps) = _computePathTokenInAndSteps(
            context,
            pool,
            poolTokenIn,
            poolTokenOut,
            needToWrapTokenIn,
            needToUnwrapTokenOut
        );

        pathTokenIn.safeTransfer(address(context.vault), exactAmountIn);

        IBatchRouter.SwapPathExactAmountIn[] memory paths = new IBatchRouter.SwapPathExactAmountIn[](1);
        paths[0] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: pathTokenIn,
            steps: steps,
            exactAmountIn: exactAmountIn,
            minAmountOut: minAmountOut
        });

        (uint256[] memory pathAmountsOut, , ) = context.aggregatorBatchRouter.swapExactIn(paths, deadline, userData);

        return pathAmountsOut[0];
    }

    function querySwapSingleTokenExactOut(
        BalancerContext memory context,
        address pool,
        IERC20 poolTokenIn,
        IERC20 poolTokenOut,
        uint256 exactAmountOut,
        uint256 maxAmountIn,
        bool needToWrapTokenIn,
        bool needToUnwrapTokenOut,
        address sender,
        bytes memory userData
    ) internal returns (uint256 amountIn) {
        (IERC20 pathTokenIn, IBatchRouter.SwapPathStep[] memory steps) = _computePathTokenInAndSteps(
            context,
            pool,
            poolTokenIn,
            poolTokenOut,
            needToWrapTokenIn,
            needToUnwrapTokenOut
        );

        IBatchRouter.SwapPathExactAmountOut[] memory paths = new IBatchRouter.SwapPathExactAmountOut[](1);
        paths[0] = IBatchRouter.SwapPathExactAmountOut({
            tokenIn: pathTokenIn,
            steps: steps,
            exactAmountOut: exactAmountOut,
            maxAmountIn: maxAmountIn
        });

        (uint256[] memory pathAmountsOut, , ) = context.aggregatorBatchRouter.querySwapExactOut(
            paths,
            sender,
            userData
        );

        return pathAmountsOut[0];
    }

    function swapSingleTokenExactOut(
        BalancerContext memory context,
        address pool,
        IERC20 poolTokenIn,
        IERC20 poolTokenOut,
        uint256 exactAmountOut,
        uint256 maxAmountIn,
        uint256 deadline,
        bytes memory userData
    ) internal returns (uint256 amountIn) {
        poolTokenIn.safeTransfer(address(context.vault), maxAmountIn);

        return
            context.aggregatorRouter.swapSingleTokenExactOut(
                pool,
                poolTokenIn,
                poolTokenOut,
                exactAmountOut,
                maxAmountIn,
                deadline,
                userData
            );
    }

    function batchSwapSingleTokenExactOut(
        BalancerContext memory context,
        address pool,
        IERC20 poolTokenIn,
        IERC20 poolTokenOut,
        uint256 exactAmountOut,
        uint256 maxAmountIn,
        uint256 deadline,
        bool needToWrapTokenIn,
        bool needToUnwrapTokenOut,
        bytes memory userData
    ) internal returns (uint256 amountIn) {
        (IERC20 pathTokenIn, IBatchRouter.SwapPathStep[] memory steps) = _computePathTokenInAndSteps(
            context,
            pool,
            poolTokenIn,
            poolTokenOut,
            needToWrapTokenIn,
            needToUnwrapTokenOut
        );

        pathTokenIn.safeTransfer(address(context.vault), maxAmountIn);

        IBatchRouter.SwapPathExactAmountOut[] memory paths = new IBatchRouter.SwapPathExactAmountOut[](1);
        paths[0] = IBatchRouter.SwapPathExactAmountOut({
            tokenIn: pathTokenIn,
            steps: steps,
            exactAmountOut: exactAmountOut,
            maxAmountIn: maxAmountIn
        });

        (uint256[] memory pathAmountsOut, , ) = context.aggregatorBatchRouter.swapExactOut(paths, deadline, userData);

        return pathAmountsOut[0];
    }

    function _computePathTokenInAndSteps(
        BalancerContext memory context,
        address pool,
        IERC20 poolTokenIn,
        IERC20 poolTokenOut,
        bool needToWrapTokenIn,
        bool needToUnwrapTokenOut
    ) private view returns (IERC20 pathTokenIn, IBatchRouter.SwapPathStep[] memory steps) {
        uint256 stepCounter = 0;
        uint256 length = 1 + (needToWrapTokenIn ? 1 : 0) + (needToUnwrapTokenOut ? 1 : 0);
        steps = new IBatchRouter.SwapPathStep[](length);

        if (needToWrapTokenIn) {
            IERC4626 wrappedTokenIn = IERC4626(address(poolTokenIn));
            IERC20 underlyingTokenIn = IERC20(context.vault.getERC4626BufferAsset(wrappedTokenIn));

            pathTokenIn = IERC20(underlyingTokenIn);
            steps[stepCounter++] = IBatchRouter.SwapPathStep({
                pool: address(wrappedTokenIn),
                tokenOut: IERC20(address(wrappedTokenIn)),
                isBuffer: true
            });
        } else {
            pathTokenIn = poolTokenIn;
        }

        steps[stepCounter++] = IBatchRouter.SwapPathStep({ pool: pool, tokenOut: poolTokenOut, isBuffer: false });

        if (needToUnwrapTokenOut) {
            IERC4626 wrappedTokenOut = IERC4626(address(poolTokenOut));
            IERC20 underlyingTokenOut = IERC20(context.vault.getERC4626BufferAsset(wrappedTokenOut));

            steps[stepCounter++] = IBatchRouter.SwapPathStep({
                pool: address(wrappedTokenOut),
                tokenOut: underlyingTokenOut,
                isBuffer: true
            });
        }
    }
}
