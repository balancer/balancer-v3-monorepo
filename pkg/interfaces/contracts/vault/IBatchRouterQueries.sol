// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { SwapPathExactAmountIn, SwapPathExactAmountOut } from "./BatchRouterTypes.sol";

/// @notice Interface for the `BatchRouter`, supporting multi-hop swaps.
interface IBatchRouterQueries {
    /**
     * @notice Queries a swap operation involving multiple paths (steps), specifying exact input token amounts.
     * @dev Min amounts out specified in the paths are ignored.
     * @param paths Swap paths from token in to token out, specifying exact amounts in
     * @param sender The sender passed to the operation. It can influence results (e.g., with user-dependent hooks)
     * @param userData Additional (optional) data required for the query
     * @return pathAmountsOut Calculated amounts of output tokens corresponding to the last step of each given path
     * @return tokensOut Output token addresses
     * @return amountsOut Calculated amounts of output tokens to be received, ordered by output token address
     */
    function querySwapExactIn(
        SwapPathExactAmountIn[] memory paths,
        address sender,
        bytes calldata userData
    ) external returns (uint256[] memory pathAmountsOut, address[] memory tokensOut, uint256[] memory amountsOut);

    /**
     * @notice Queries a swap operation involving multiple paths (steps), specifying exact output token amounts.
     * @dev Max amounts in specified in the paths are ignored.
     * @param paths Swap paths from token in to token out, specifying exact amounts out
     * @param sender The sender passed to the operation. It can influence results (e.g., with user-dependent hooks)
     * @param userData Additional (optional) data required for the query
     * @return pathAmountsIn Calculated amounts of input tokens corresponding to the last step of each given path
     * @return tokensIn Input token addresses
     * @return amountsIn Calculated amounts of input tokens to be received, ordered by input token address
     */
    function querySwapExactOut(
        SwapPathExactAmountOut[] memory paths,
        address sender,
        bytes calldata userData
    ) external returns (uint256[] memory pathAmountsIn, address[] memory tokensIn, uint256[] memory amountsIn);
}
