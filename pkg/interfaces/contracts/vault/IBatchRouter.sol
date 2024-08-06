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
        // if true, pool is a yield-bearing token buffer. Used to wrap/unwrap tokens if pool doesn't have
        // enough liquidity
        bool isBuffer;
    }

    struct SwapPathExactAmountIn {
        IERC20 tokenIn;
        // for each step:
        // if tokenIn == pool, use removeLiquidity SINGLE_TOKEN_EXACT_IN
        // if tokenOut == pool, use addLiquidity UNBALANCED
        SwapPathStep[] steps;
        uint256 exactAmountIn;
        uint256 minAmountOut;
    }

    struct SwapPathExactAmountOut {
        IERC20 tokenIn;
        // for each step:
        // if tokenIn == pool, use removeLiquidity SINGLE_TOKEN_EXACT_OUT
        // if tokenOut == pool, use addLiquidity SINGLE_TOKEN_EXACT_OUT
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

    /***************************************************************************
                                   ERC4626 Pools
    ***************************************************************************/
    // These functions allow interacting with ERC4626 Pools (which are composed of wrapped ERC4626 tokens) using only
    // underlying standard tokens. For instance, with `addLiquidityUnbalancedToERC4626Pool` it is possible to add
    // liquidity to an ERC4626 Pool with [waDAI, waUSDC], using only DAI, only USDC, or an arbitrary amount of both.
    // If the ERC4626 buffers in the Vault have liquidity, these will be used to avoid wrapping/unwrapping through
    // the wrapped token interface, saving gas.
    //
    // For instance, adding only DAI to the pool above (and assuming an aDAI buffer with enough liquidity), would
    // pull in the DAI from the user, swap it for waDAI in the internal Vault buffer, and deposit the waDAI into the
    // ERC4626 pool: 1) without having to do any expensive ERC4626 wrapping operations; and 2) without requiring the
    // user to construct a batch operation containing the buffer swap.

    /**
     * @dev An "ERC4626 pool" is one in which all tokens conform to the IERC4626 yield-bearing token standard (e.g., waDAI).
     * @notice Add arbitrary amounts of underlying tokens to an ERC4626 pool through the buffer.
     * @param pool Address of the liquidity pool
     * @param exactUnderlyingAmountsIn Exact amounts of underlying tokens to be added, sorted in token registration order
     * @param minBptAmountOut Minimum amount of pool tokens to be received
     * @param wethIsEth If true, incoming ETH will be wrapped to WETH and outgoing WETH will be unwrapped to ETH
     * @param userData Additional (optional) data required for adding liquidity
     * @return bptAmountOut Actual amount of pool tokens received
     */
    function addLiquidityUnbalancedToERC4626Pool(
        address pool,
        uint256[] memory exactUnderlyingAmountsIn,
        uint256 minBptAmountOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable returns (uint256 bptAmountOut);

    /**
     * @dev An "ERC4626 pool" is one in which all tokens conform to the IERC4626 yield-bearing token standard (e.g., waDAI).
     * @notice Add proportional amounts of underlying tokens to an ERC4626 pool through the buffer.
     * @param pool Address of the liquidity pool
     * @param maxUnderlyingAmountsIn Maximum amounts of underlying tokens to be added, sorted in token registration order
     * @param exactBptAmountOut Exact amount of pool tokens to be received
     * @param wethIsEth If true, incoming ETH will be wrapped to WETH and outgoing WETH will be unwrapped to ETH
     * @param userData Additional (optional) data required for adding liquidity
     * @return underlyingAmountsIn Actual amounts of tokens added, sorted in token registration order
     */
    function addLiquidityProportionalToERC4626Pool(
        address pool,
        uint256[] memory maxUnderlyingAmountsIn,
        uint256 exactBptAmountOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable returns (uint256[] memory underlyingAmountsIn);

    /**
     * @dev An "ERC4626 pool" is one in which all tokens conform to the IERC4626 yield-bearing token standard (e.g., waDAI).
     * @notice Remove proportional amounts of underlying tokens from an ERC4626 pool, burning an exact pool token amount.
     * @param pool Address of the liquidity pool
     * @param exactBptAmountIn Exact amount of pool tokens provided
     * @param minUnderlyingAmountsOut Minimum amounts of underlying tokens to be received, sorted in token registration order
     * @param wethIsEth If true, incoming ETH will be wrapped to WETH and outgoing WETH will be unwrapped to ETH
     * @param userData Additional (optional) data required for removing liquidity
     * @return underlyingAmountsOut Actual amounts of tokens received, sorted in token registration order
     */
    function removeLiquidityProportionalFromERC4626Pool(
        address pool,
        uint256 exactBptAmountIn,
        uint256[] memory minUnderlyingAmountsOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable returns (uint256[] memory underlyingAmountsOut);

    /**
     * @dev An "ERC4626 pool" is one in which all tokens conform to the IERC4626 yield-bearing token standard (e.g., waDAI).
     * @notice Queries an `addLiquidityUnbalancedToERC4626Pool` operation without actually executing it.
     * @param pool Address of the liquidity pool
     * @param exactUnderlyingAmountsIn Exact amounts of underlying tokens to be added, sorted in token registration order
     * @param userData Additional (optional) data required for the query
     * @return bptAmountOut Expected amount of pool tokens to receive
     */
    function queryAddLiquidityUnbalancedToERC4626Pool(
        address pool,
        uint256[] memory exactUnderlyingAmountsIn,
        bytes memory userData
    ) external returns (uint256 bptAmountOut);

    /**
     * @dev An "ERC4626 pool" is one in which all tokens conform to the IERC4626 yield-bearing token standard (e.g., waDAI).
     * @notice Queries an `addLiquidityProportionalToERC4626Pool` operation without actually executing it.
     * @param pool Address of the liquidity pool
     * @param exactBptAmountOut Exact amount of pool tokens to be received
     * @param userData Additional (optional) data required for the query
     * @return underlyingAmountsIn Expected amounts of tokens to add, sorted in token registration order
     */
    function queryAddLiquidityProportionalToERC4626Pool(
        address pool,
        uint256 exactBptAmountOut,
        bytes memory userData
    ) external returns (uint256[] memory underlyingAmountsIn);

    /**
     * @dev An "ERC4626 pool" is one in which all tokens conform to the IERC4626 yield-bearing token standard (e.g., waDAI).
     * @notice Queries a `removeLiquidityProportionalFromERC4626Pool` operation without actually executing it.
     * @param pool Address of the liquidity pool
     * @param exactBptAmountIn Exact amount of pool tokens provided for the query
     * @param userData Additional (optional) data required for the query
     * @return underlyingAmountsOut Expected amounts of tokens to receive, sorted in token registration order
     */
    function queryRemoveLiquidityProportionalFromERC4626Pool(
        address pool,
        uint256 exactBptAmountIn,
        bytes memory userData
    ) external returns (uint256[] memory underlyingAmountsOut);
}
