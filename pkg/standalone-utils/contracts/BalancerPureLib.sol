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

/// @notice Store contract addresses used by library functions.
struct BalancerContext {
    IAggregatorRouter aggregatorRouter;
    IAggregatorBatchRouter aggregatorBatchRouter;
    IVault vault;
}

/// @notice Gas-optimized Balancer utility library for direct low-level operations
library BalancerPureLib {
    using SafeERC20 for IERC20;

    uint256 private constant _MAX_UINT128 = type(uint128).max;

    /**
     * @notice Create a context for Balancer library functions.
     * @param aggregatorRouter The address of the Aggregator Router
     * @param aggregatorBatchRouter The address of the Aggregator Batch Router
     */
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

    /***************************************************************************
                                   Swap Exact In
    ***************************************************************************/

    /**
     * @notice Queries a swap operation specifying an exact input token amount without actually executing it.
     * @dev This function uses the Aggregator Batch Router
     * @param pool Address of the liquidity pool
     * @param poolTokenIn Pool token to be swapped from
     * @param poolTokenOut Pool token to be swapped to
     * @param exactAmountIn Exact amounts of input tokens to send
     * @param needToWrapTokenIn Whether the input token needs to be wrapped (e.g., from ERC20 to ERC4626)
     * @param needToUnwrapTokenOut Whether the output token needs to be unwrapped (e.g., from ERC4626 to ERC20)
     * @param sender The sender passed to the operation. It can influence results (e.g., with user-dependent hooks)
     * @param userData Additional (optional) data sent with the query request
     * @return amountOut Calculated amount of output tokens, denominated in the final token received:
     * if the operation performs an unwrap step, amountOut is expressed in the underlying token,
     * otherwise, it is expressed in poolTokenOut.
     */
    function querySwapSingleTokenExactIn(
        BalancerContext memory context,
        address pool,
        IERC20 poolTokenIn,
        IERC20 poolTokenOut,
        uint256 exactAmountIn,
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
            minAmountOut: 0
        });

        (uint256[] memory pathAmountsOut, , ) = context.aggregatorBatchRouter.querySwapExactIn(paths, sender, userData);

        return pathAmountsOut[0];
    }

    /**
     * @notice Executes a swap operation specifying an exact input token amount.
     * @dev This function uses the Aggregator Router directly
     * @param pool Address of the liquidity pool
     * @param poolTokenIn Pool token to be swapped from
     * @param poolTokenOut Pool token to be swapped to
     * @param exactAmountIn Exact amounts of input tokens to send
     * @param minAmountOut Minimum amount of tokens to be received
     * @param deadline Deadline for the swap, after which it will revert
     * @param userData Additional (optional) data sent with the query request\
     * @return amountOut Calculated amount of output tokens to be received in exchange for the given input tokens
     */
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

    /**
     * @notice Executes a swap operation specifying an exact input token amount.
     * @dev This function uses the Aggregator Batch Router
     * @param pool Address of the liquidity pool
     * @param poolTokenIn Pool token to be swapped from
     * @param poolTokenOut Pool token to be swapped to
     * @param exactAmountIn Exact amounts of input tokens to send
     * @param minAmountOut Minimum amount of tokens to be received
     * @param deadline Deadline for the swap, after which it will revert
     * @param needToWrapTokenIn Whether the input token needs to be wrapped (e.g., from ERC20 to ERC4626)
     * @param needToUnwrapTokenOut Whether the output token needs to be unwrapped (e.g., from ERC4626 to ERC20)
     * @param userData Additional (optional) data sent with the query request
     * @return amountOut Calculated amount of output tokens, denominated in the final token received:
     * if the operation performs an unwrap step, amountOut is expressed in the underlying token,
     * otherwise, it is expressed in poolTokenOut.
     */
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

    /***************************************************************************
                                   Swap Exact Out
    ***************************************************************************/

    /**
     * @notice Queries a swap operation specifying an exact output token amount without actually executing it.
     * @dev This function uses the Aggregator Batch Router
     * @param pool Address of the liquidity pool
     * @param poolTokenIn Token to be swapped from
     * @param poolTokenOut Token to be swapped to
     * @param exactAmountOut Exact amounts of input tokens to receive
     * @param needToWrapTokenIn Whether the input token needs to be wrapped (e.g., from ERC20 to ERC4626)
     * @param needToUnwrapTokenOut Whether the output token needs to be unwrapped (e.g., from ERC4626 to ERC20)
     * @param sender The sender passed to the operation. It can influence results (e.g., with user-dependent hooks)
     * @param userData Additional (optional) data sent with the query request
     * @return amountIn Calculated amount of input tokens, denominated in the token actually provided by the caller:
     * if wrapping is required, amountIn is expressed in the underlying token of poolTokenIn,
     * otherwise, it is expressed in poolTokenIn.
     */
    function querySwapSingleTokenExactOut(
        BalancerContext memory context,
        address pool,
        IERC20 poolTokenIn,
        IERC20 poolTokenOut,
        uint256 exactAmountOut,
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
            maxAmountIn: _MAX_UINT128
        });

        (uint256[] memory pathAmountsOut, , ) = context.aggregatorBatchRouter.querySwapExactOut(
            paths,
            sender,
            userData
        );

        return pathAmountsOut[0];
    }

    /**
     * @notice Executes a swap operation specifying an exact output token amount.
     * @dev This function uses the Aggregator Router
     * @param pool Address of the liquidity pool
     * @param poolTokenIn Token to be swapped from
     * @param poolTokenOut Token to be swapped to
     * @param exactAmountOut Exact amounts of input tokens to receive
     * @param maxAmountIn Maximum amount of tokens to be sent
     * @param deadline Deadline for the swap, after which it will revert
     * @param userData Additional (optional) data sent with the swap request
     * @return amountIn Calculated amount of input tokens to be sent in exchange for the requested output tokens
     */
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

    /**
     * @notice Executes a swap operation specifying an exact output token amount.
     * @dev This function uses the Aggregator Batch Router
     * @param pool Address of the liquidity pool
     * @param poolTokenIn Token to be swapped from
     * @param poolTokenOut Token to be swapped to
     * @param exactAmountOut Exact amounts of input tokens to receive
     * @param needToWrapTokenIn Whether the input token needs to be wrapped (e.g., from ERC20 to ERC4626)
     * @param needToUnwrapTokenOut Whether the output token needs to be unwrapped (e.g., from ERC4626 to ERC20)
     * @param maxAmountIn Maximum amount of tokens to be sent
     * @param deadline Deadline for the swap, after which it will revert
     * @param userData Additional (optional) data sent with the swap request
     * @return amountIn Calculated amount of input tokens, denominated in the token actually provided by the caller:
     * if wrapping is required, amountIn is expressed in the underlying token of poolTokenIn,
     * otherwise, it is expressed in poolTokenIn.
     */
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
