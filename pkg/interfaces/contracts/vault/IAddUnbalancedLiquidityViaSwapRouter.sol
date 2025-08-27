// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./RouterTypes.sol";

/// @notice Router interface for adding unbalanced liquidity via a combination of a proportional add and a swap.
interface IAddUnbalancedLiquidityViaSwapRouter {
    struct SwapParams {
        IERC20 tokenIn;
        IERC20 tokenOut;
        SwapKind kind;
        uint256 amountGiven;
        uint256 limit;
        bytes userData;
    }

    struct AddLiquidityProportionalParams {
        uint256[] maxAmountsIn;
        uint256 exactBptAmountOut;
        bytes userData;
    }

    struct AddLiquidityAndSwapHookParams {
        AddLiquidityHookParams addLiquidityParams;
        SwapSingleTokenHookParams swapParams;
    }

    /**
     * @notice Adds liquidity to a pool with proportional token amounts and an ExactIn swap in the same transaction.
     * @param pool Address of the liquidity pool
     * @param deadline Timestamp after which the transaction will revert
     * @param wethIsEth If true, incoming ETH will be wrapped to WETH and outgoing WETH will be unwrapped to ETH
     * @param addLiquidityParams Parameters for adding liquidity
     * @param swapParams Parameters for the swap operation
     * @return amountsIn Array of amounts in for each token added to the pool, sorted in token registration order.
     * @return swapAmountOut Swap amount out for the swap operation
     */
    function addUnbalancedLiquidityViaSwapExactIn(
        address pool,
        uint256 deadline,
        bool wethIsEth,
        AddLiquidityProportionalParams calldata addLiquidityParams,
        SwapParams calldata swapParams
    ) external payable returns (uint256[] memory amountsIn, uint256 swapAmountOut);

    /**
     * @notice Adds liquidity to a pool with proportional token amounts and an ExactOut swap in the same transaction.
     * @param pool Address of the liquidity pool
     * @param deadline Timestamp after which the transaction will revert
     * @param wethIsEth If true, incoming ETH will be wrapped to WETH and outgoing WETH will be unwrapped to ETH
     * @param addLiquidityParams Parameters for adding liquidity
     * @param swapParams Parameters for the swap operation
     * @return amountsIn Array of amounts in for each token added to the pool, sorted in token registration order.
     * @return swapAmountIn Swap amount in for the swap operation
     */
    function addUnbalancedLiquidityViaSwapExactOut(
        address pool,
        uint256 deadline,
        bool wethIsEth,
        AddLiquidityProportionalParams calldata addLiquidityParams,
        SwapParams calldata swapParams
    ) external payable returns (uint256[] memory amountsIn, uint256 swapAmountIn);

    /**
     * @notice Queries an `addUnbalancedLiquidityViaSwapExactIn` operation without actually executing it.
     * @param pool Address of the liquidity pool
     * @param sender The sender passed to the operation. It can influence results (e.g., with user-dependent hooks)
     * @param addLiquidityParams Parameters for adding liquidity
     * @param swapParams Parameters for the swap operation
     * @return amountsIn Array of amounts in for each token added to the pool, sorted in token registration order.
     * @return swapAmountOut Swap amount out for the swap operation
     */
    function queryAddUnbalancedLiquidityViaSwapExactIn(
        address pool,
        address sender,
        AddLiquidityProportionalParams calldata addLiquidityParams,
        SwapParams calldata swapParams
    ) external returns (uint256[] memory amountsIn, uint256 swapAmountOut);

    /**
     * @notice Queries an `addUnbalancedLiquidityViaSwapExactOut` operation without actually executing it.
     * @param pool Address of the liquidity pool
     * @param sender The sender passed to the operation. It can influence results (e.g., with user-dependent hooks)
     * @param addLiquidityParams Parameters for adding liquidity
     * @param swapParams Parameters for the swap operation
     * @return amountsIn Array of amounts in for each token added to the pool, sorted in token registration order.
     * @return swapAmountIn Swap amount in for the swap operation
     */
    function queryAddUnbalancedLiquidityViaSwapExactOut(
        address pool,
        address sender,
        AddLiquidityProportionalParams calldata addLiquidityParams,
        SwapParams calldata swapParams
    ) external returns (uint256[] memory amountsIn, uint256 swapAmountIn);
}
