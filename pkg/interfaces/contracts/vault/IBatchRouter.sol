// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { SwapPathExactAmountIn, SwapPathExactAmountOut } from "./BatchRouterTypes.sol";
import "./IBatchRouterQueries.sol";

/// @notice Interface for the `BatchRouter`, supporting multi-hop swaps.
interface IBatchRouter is IBatchRouterQueries {
    /**
     * @notice Executes a swap operation involving multiple paths (steps), specifying exact input token amounts.
     * @param paths Swap paths from token in to token out, specifying exact amounts in
     * @param deadline Deadline for the swap, after which it will revert
     * @param wethIsEth If true, incoming ETH will be wrapped to WETH and outgoing WETH will be unwrapped to ETH
     * @param userData Additional (optional) data required for the swap
     * @return pathAmountsOut Calculated amounts of output tokens corresponding to the last step of each given path
     * @return tokensOut Output token addresses
     * @return amountsOut Calculated amounts of output tokens, ordered by output token address
     */
    function swapExactIn(
        SwapPathExactAmountIn[] memory paths,
        uint256 deadline,
        bool wethIsEth,
        bytes calldata userData
    )
        external
        payable
        returns (uint256[] memory pathAmountsOut, address[] memory tokensOut, uint256[] memory amountsOut);

    /**
     * @notice Executes a swap operation involving multiple paths (steps), specifying exact output token amounts.
     * @param paths Swap paths from token in to token out, specifying exact amounts out
     * @param deadline Deadline for the swap
     * @param wethIsEth If true, incoming ETH will be wrapped to WETH and outgoing WETH will be unwrapped to ETH
     * @param userData Additional (optional) data required for the swap
     * @return pathAmountsIn Calculated amounts of input tokens corresponding to the first step of each given path
     * @return tokensIn Input token addresses
     * @return amountsIn Calculated amounts of input tokens, ordered by input token address
     */
    function swapExactOut(
        SwapPathExactAmountOut[] memory paths,
        uint256 deadline,
        bool wethIsEth,
        bytes calldata userData
    ) external payable returns (uint256[] memory pathAmountsIn, address[] memory tokensIn, uint256[] memory amountsIn);
}
