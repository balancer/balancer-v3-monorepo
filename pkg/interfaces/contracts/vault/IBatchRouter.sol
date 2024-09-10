// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { AddLiquidityKind, RemoveLiquidityKind, SwapKind } from "./VaultTypes.sol";

/// @notice Interface for the batch router, supporting multi-hop swaps.
interface IBatchRouter {
    /***************************************************************************
                                       Swaps
    ***************************************************************************/

    struct SwapPathStep {
        address pool;
        IERC20 tokenOut;
        // If true, the "pool" is an ERC4626 Buffer. Used to wrap/unwrap tokens if pool doesn't have enough liquidity.
        bool isBuffer;
    }

    struct SwapPathExactAmountIn {
        IERC20 tokenIn;
        // For each step:
        // If tokenIn == pool, use removeLiquidity SINGLE_TOKEN_EXACT_IN.
        // If tokenOut == pool, use addLiquidity UNBALANCED.
        SwapPathStep[] steps;
        uint256 exactAmountIn;
        uint256 minAmountOut;
    }

    struct SwapPathExactAmountOut {
        IERC20 tokenIn;
        // for each step:
        // If tokenIn == pool, use removeLiquidity SINGLE_TOKEN_EXACT_OUT.
        // If tokenOut == pool, use addLiquidity SINGLE_TOKEN_EXACT_OUT.
        SwapPathStep[] steps;
        uint256 maxAmountIn;
        uint256 exactAmountOut;
    }

    struct SwapExactInHookParams {
        address sender;
        SwapPathExactAmountIn[] paths;
        uint256 deadline;
        bool wethIsEth;
        bytes userData;
    }

    struct SwapExactOutHookParams {
        address sender;
        SwapPathExactAmountOut[] paths;
        uint256 deadline;
        bool wethIsEth;
        bytes userData;
    }

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

    /***************************************************************************
                                     Queries
    ***************************************************************************/

    /**
     * @notice Queries a swap operation involving multiple paths (steps), specifying exact input token amounts.
     * @dev Min amounts out specified in the paths are ignored.
     * @param paths Swap paths from token in to token out, specifying exact amounts in
     * @param userData Additional (optional) data required for the query
     * @return pathAmountsOut Calculated amounts of output tokens corresponding to the last step of each given path
     * @return tokensOut Output token addresses
     * @return amountsOut Calculated amounts of output tokens to be received, ordered by output token address
     */
    function querySwapExactIn(
        SwapPathExactAmountIn[] memory paths,
        bytes calldata userData
    ) external returns (uint256[] memory pathAmountsOut, address[] memory tokensOut, uint256[] memory amountsOut);

    /**
     * @notice Queries a swap operation involving multiple paths (steps), specifying exact output token amounts.
     * @dev Max amounts in specified in the paths are ignored.
     * @param paths Swap paths from token in to token out, specifying exact amounts out
     * @param userData Additional (optional) data required for the query
     * @return pathAmountsIn Calculated amounts of input tokens corresponding to the last step of each given path
     * @return tokensIn Input token addresses
     * @return amountsIn Calculated amounts of input tokens to be received, ordered by input token address
     */
    function querySwapExactOut(
        SwapPathExactAmountOut[] memory paths,
        bytes calldata userData
    ) external returns (uint256[] memory pathAmountsIn, address[] memory tokensIn, uint256[] memory amountsIn);
}
