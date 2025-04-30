// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { AddLiquidityKind, RemoveLiquidityKind, SwapKind } from "./VaultTypes.sol";
import { IBatchRouter } from "./IBatchRouter.sol";

/// @notice Interface for the `AggregatorBatchRouter`, supporting multi-hop swaps prepaid by the caller.
interface IAggregatorBatchRouter {
    /**
     * @notice Executes a swap operation involving multiple paths (steps), specifying exact input token amounts.
     * @param paths Swap paths from token in to token out, specifying exact amounts in
     * @param deadline Deadline for the swap, after which it will revert
     * @param userData Additional (optional) data required for the swap
     * @return pathAmountsOut Calculated amounts of output tokens corresponding to the last step of each given path
     * @return tokensOut Output token addresses
     * @return amountsOut Calculated amounts of output tokens, ordered by output token address
     */
    function swapExactIn(
        IBatchRouter.SwapPathExactAmountIn[] memory paths,
        uint256 deadline,
        bytes calldata userData
    )
        external
        payable
        returns (uint256[] memory pathAmountsOut, address[] memory tokensOut, uint256[] memory amountsOut);

    /**
     * @notice Executes a swap operation involving multiple paths (steps), specifying exact output token amounts.
     * @param paths Swap paths from token in to token out, specifying exact amounts out
     * @param deadline Deadline for the swap
     * @param userData Additional (optional) data required for the swap
     * @return pathAmountsIn Calculated amounts of input tokens corresponding to the first step of each given path
     * @return tokensIn Input token addresses
     * @return amountsIn Calculated amounts of input tokens, ordered by input token address
     */
    function swapExactOut(
        IBatchRouter.SwapPathExactAmountOut[] memory paths,
        uint256 deadline,
        bytes calldata userData
    ) external payable returns (uint256[] memory pathAmountsIn, address[] memory tokensIn, uint256[] memory amountsIn);

    /***************************************************************************
                                     Queries
    ***************************************************************************/

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
        IBatchRouter.SwapPathExactAmountIn[] memory paths,
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
        IBatchRouter.SwapPathExactAmountOut[] memory paths,
        address sender,
        bytes calldata userData
    ) external returns (uint256[] memory pathAmountsIn, address[] memory tokensIn, uint256[] memory amountsIn);
}
