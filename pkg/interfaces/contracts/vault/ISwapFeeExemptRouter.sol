// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @notice Basic interface for a router that provides simple swap functionality.
 * @dev Phase 1: Open router that anyone can use for swaps.
 */
interface ISwapFeeExemptRouter {
    /**
     * @notice Executes a swap with exact input amount.
     * @param pool Address of the pool to swap with
     * @param tokenIn Token to be swapped from
     * @param tokenOut Token to be swapped to
     * @param exactAmountIn Exact amount of tokenIn to be swapped
     * @param minAmountOut Minimum amount of tokenOut to be received
     * @param deadline Time limit for the swap (timestamp)
     * @param wethIsEth If true, incoming ETH will be wrapped to WETH and outgoing WETH will be unwrapped to ETH
     * @param userData Additional (optional) data sent with the swap request
     * @return amountOut The amount of tokens received
     */
    function swapSingleTokenExactIn(
        address pool,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 exactAmountIn,
        uint256 minAmountOut,
        uint256 deadline,
        bool wethIsEth,
        bytes calldata userData
    ) external payable returns (uint256 amountOut);

    /**
     * @notice Executes a swap with exact output amount.
     * @param pool Address of the pool to swap with
     * @param tokenIn Token to be swapped from
     * @param tokenOut Token to be swapped to  
     * @param exactAmountOut Exact amount of tokenOut to be received
     * @param maxAmountIn Maximum amount of tokenIn to be spent
     * @param deadline Time limit for the swap (timestamp)
     * @param wethIsEth If true, incoming ETH will be wrapped to WETH and outgoing WETH will be unwrapped to ETH
     * @param userData Additional (optional) data sent with the swap request
     * @return amountIn The amount of tokens required
     */    
    function swapSingleTokenExactOut(
        address pool,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 exactAmountOut,
        uint256 maxAmountIn,
        uint256 deadline,
        bool wethIsEth,
        bytes calldata userData
    ) external payable returns (uint256 amountIn);
}