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

/// @notice User friendly library for Balancer swap operations.
library BalancerSwapLib {
    using SafeERC20 for IERC20;

    /// @notice Common parameters for swap operations
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

    /// @notice Swap Exact In parameters
    struct SwapExactInParams {
        CommonParams common;
        uint256 exactAmountIn;
        uint256 minAmountOut;
    }

    /// @notice Swap Exact Out parameters
    struct SwapExactOutParams {
        CommonParams common;
        uint256 exactAmountOut;
        uint256 maxAmountIn;
    }

    /**
     * @notice Create a context for Balancer library functions.
     * @param aggregatorRouter The address of the Aggregator Router
     * @param aggregatorBatchRouter The address of the Aggregator Batch Router
     */
    function createContext(
        address aggregatorRouter,
        address aggregatorBatchRouter
    ) internal view returns (BalancerContext memory) {
        return BalancerPureLib.createContext(aggregatorRouter, aggregatorBatchRouter);
    }

    /***************************************************************************
                                   Swap Exact In
    ***************************************************************************/

    /**
     * @notice Build parameters for a swap operation specifying an exact input token amount. 
     * The debited token will be poolTokenIn if wrapping is not required, 
     * and the underlying token if wrapping is required.

     * @param pool Address of the liquidity pool
     * @param poolTokenIn Pool token to be swapped from
     * @param poolTokenOut Pool token to be swapped to
     * @param exactAmountIn Exact amounts of input tokens to send
     * @param minAmountOut Minimum amount of tokens to be received
     * @param deadline Deadline for the swap, after which it will revert
     * @return params Struct containing the parameters for the swap exact in operation
     */
    function buildSwapExactIn(
        BalancerContext memory ctx,
        address pool,
        IERC20 poolTokenIn,
        IERC20 poolTokenOut,
        uint256 exactAmountIn,
        uint256 minAmountOut,
        uint256 deadline
    ) internal pure returns (SwapExactInParams memory params) {
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

    /**
     * @notice Wrap the input token in the swap operation.
     * @param params The parameters for the swap operation
     */
    function wrapTokenIn(SwapExactInParams memory params) internal pure returns (SwapExactInParams memory) {
        params.common.wrapTokenIn = true;
        return params;
    }

    /**
     * @notice Unwrap the output token in the swap operation.
     * @param params The parameters for the swap operation
     */
    function unwrapTokenOut(SwapExactInParams memory params) internal pure returns (SwapExactInParams memory) {
        params.common.unwrapTokenOut = true;
        return params;
    }

    /**
     * @notice Add user data to the swap operation.
     * @param params The parameters for the swap operation
     * @param userData Additional data to be included in the swap
     */
    function withUserData(
        SwapExactInParams memory params,
        bytes memory userData
    ) internal pure returns (SwapExactInParams memory) {
        params.common.userData = userData;
        return params;
    }

    /**
     * @notice Execute the swap operation with the specified parameters.
     * @param params The parameters for the swap operation
     * @return amountOut Calculated amount of output tokens, denominated in the final token received:
     * if the operation performs an unwrap step, amountOut is expressed in the underlying token,
     * otherwise, it is expressed in poolTokenOut.
     */
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

    /**
     * @notice Query the swap operation with the specified parameters.
     * Minimum amount of tokens ignored in the query.
     *
     * @param params The parameters for the swap operation
     * @param sender The sender of the swap request
     * @return amountOut Calculated amount of output tokens, denominated in the final token received:
     * if the operation performs an unwrap step, amountOut is expressed in the underlying token,
     * otherwise, it is expressed in poolTokenOut.
     */
    function query(SwapExactInParams memory params, address sender) internal returns (uint256 amountOut) {
        return
            BalancerPureLib.querySwapSingleTokenExactIn(
                params.common.context,
                params.common.pool,
                params.common.poolTokenIn,
                params.common.poolTokenOut,
                params.exactAmountIn,
                params.common.wrapTokenIn,
                params.common.unwrapTokenOut,
                sender,
                params.common.userData
            );
    }

    /***************************************************************************
                                   Swap Exact Out
    ***************************************************************************/

    /**
     * @notice Build parameters for a swap operation specifying an exact out token amount.
     * The debited token will be poolTokenIn if wrapping is not required,
     * and the underlying token if wrapping is required.
     * @param pool Address of the liquidity pool
     * @param poolTokenIn Token to be swapped from
     * @param poolTokenOut Token to be swapped to
     * @param exactAmountOut Exact amounts of input tokens to receive
     * @param maxAmountIn Maximum amount of tokens to be sent
     * @param deadline Deadline for the swap, after which it will revert
     * @return params Struct containing the parameters for the swap exact out operation
     */
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

    /**
     * @notice Wrap the input token in the swap operation.
     * @param params The parameters for the swap operation
     */
    function wrapTokenIn(SwapExactOutParams memory params) internal pure returns (SwapExactOutParams memory) {
        params.common.wrapTokenIn = true;
        return params;
    }

    /**
     * @notice Unwrap the output token in the swap operation.
     * @param params The parameters for the swap operation
     */
    function unwrapTokenOut(SwapExactOutParams memory params) internal pure returns (SwapExactOutParams memory) {
        params.common.unwrapTokenOut = true;
        return params;
    }

    /**
     * @notice Add user data to the swap operation.
     * @param params The parameters for the swap operation
     * @param userData Additional data to be included in the swap
     */
    function withUserData(
        SwapExactOutParams memory params,
        bytes memory userData
    ) internal pure returns (SwapExactOutParams memory) {
        params.common.userData = userData;
        return params;
    }

    /**
     * @notice Execute the swap operation with the specified parameters.
     * @param params The parameters for the swap operation
     * @return amountIn Calculated amount of input tokens, denominated in the token actually provided by the caller:
     * if wrapping is required, amountIn is expressed in the underlying token of poolTokenIn;
     * otherwise, it is expressed in poolTokenIn.
     */
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

    /**
     * @notice Query the swap operation with the specified parameters.
     * Maximum amount of tokens ignored in the query.
     *
     * @param params The parameters for the swap operation
     * @param sender The sender of the swap request
     * @return amountIn Calculated amount of input tokens, denominated in the token actually provided by the caller:
     * if wrapping is required, amountIn is expressed in the underlying token of poolTokenIn;
     * otherwise, it is expressed in poolTokenIn.
     */
    function query(SwapExactOutParams memory params, address sender) internal returns (uint256 amountIn) {
        return
            BalancerPureLib.querySwapSingleTokenExactOut(
                params.common.context,
                params.common.pool,
                params.common.poolTokenIn,
                params.common.poolTokenOut,
                params.exactAmountOut,
                params.common.wrapTokenIn,
                params.common.unwrapTokenOut,
                sender,
                params.common.userData
            );
    }
}
