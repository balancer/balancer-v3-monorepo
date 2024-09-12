// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { AddLiquidityKind, RemoveLiquidityKind, SwapKind } from "./VaultTypes.sol";

/// @notice The composite liquidity router supports add/remove liquidity operations on ERC4626 and nested pools.
interface ICompositeLiquidityRouter {
    error WrongTokensOut(address[] expectedTokensOut, address[] tokensOut);

    error WrongMinAmountsOutLength();

    /***************************************************************************
                                   ERC4626 Pools
    ***************************************************************************/
    // These functions allow interacting with ERC4626 Pools (which contain wrapped ERC4626 tokens) using only
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
     * @notice Add arbitrary amounts of underlying tokens to an ERC4626 pool through the buffer.
     * @dev An "ERC4626 pool" contains IERC4626 yield-bearing tokens (e.g., waDAI).
     * @param pool Address of the liquidity pool
     * @param exactUnderlyingAmountsIn Exact amounts of underlying tokens in, sorted in token registration order of
     * wrapped tokens in the pool
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
     * @notice Add proportional amounts of underlying tokens to an ERC4626 pool through the buffer.
     * @dev An "ERC4626 pool" contains IERC4626 yield-bearing tokens (e.g., waDAI).
     * @param pool Address of the liquidity pool
     * @param maxUnderlyingAmountsIn Maximum amounts of underlying tokens in, sorted in token registration order of
     * wrapped tokens in the pool
     * @param exactBptAmountOut Exact amount of pool tokens to be received
     * @param wethIsEth If true, incoming ETH will be wrapped to WETH and outgoing WETH will be unwrapped to ETH
     * @param userData Additional (optional) data required for adding liquidity
     * @return underlyingAmountsIn Actual amounts of tokens added, sorted in token registration order of wrapped tokens
     * in the pool
     */
    function addLiquidityProportionalToERC4626Pool(
        address pool,
        uint256[] memory maxUnderlyingAmountsIn,
        uint256 exactBptAmountOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable returns (uint256[] memory underlyingAmountsIn);

    /**
     * @notice Remove proportional amounts of underlying from an ERC4626 pool, burning an exact pool token amount.
     * @dev An "ERC4626 pool" contains IERC4626 yield-bearing tokens (e.g., waDAI).
     * @param pool Address of the liquidity pool
     * @param exactBptAmountIn Exact amount of pool tokens provided
     * @param minUnderlyingAmountsOut Minimum amounts of underlying tokens out, sorted in token registration order of
     * wrapped tokens in the pool
     * @param wethIsEth If true, incoming ETH will be wrapped to WETH and outgoing WETH will be unwrapped to ETH
     * @param userData Additional (optional) data required for removing liquidity
     * @return underlyingAmountsOut Actual amounts of tokens received, sorted in token registration order of wrapped
     * tokens in the pool
     */
    function removeLiquidityProportionalFromERC4626Pool(
        address pool,
        uint256 exactBptAmountIn,
        uint256[] memory minUnderlyingAmountsOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable returns (uint256[] memory underlyingAmountsOut);

    /**
     * @notice Queries an `addLiquidityUnbalancedToERC4626Pool` operation without actually executing it.
     * @dev An "ERC4626 pool" contains IERC4626 yield-bearing tokens (e.g., waDAI).
     * @param pool Address of the liquidity pool
     * @param exactUnderlyingAmountsIn Exact amounts of underlying tokens in, sorted in token registration order of
     * wrapped tokens in the pool
     * @param userData Additional (optional) data required for the query
     * @return bptAmountOut Expected amount of pool tokens to receive
     */
    function queryAddLiquidityUnbalancedToERC4626Pool(
        address pool,
        uint256[] memory exactUnderlyingAmountsIn,
        bytes memory userData
    ) external returns (uint256 bptAmountOut);

    /**
     * @notice Queries an `addLiquidityProportionalToERC4626Pool` operation without actually executing it.
     * @dev An "ERC4626 pool" contains IERC4626 yield-bearing tokens (e.g., waDAI).
     * @param pool Address of the liquidity pool
     * @param exactBptAmountOut Exact amount of pool tokens to be received
     * @param userData Additional (optional) data required for the query
     * @return underlyingAmountsIn Expected amounts of tokens to add, sorted in token registration order of wrapped
     * tokens in the pool
     */
    function queryAddLiquidityProportionalToERC4626Pool(
        address pool,
        uint256 exactBptAmountOut,
        bytes memory userData
    ) external returns (uint256[] memory underlyingAmountsIn);

    /**
     * @notice Queries a `removeLiquidityProportionalFromERC4626Pool` operation without actually executing it.
     * @dev An "ERC4626 pool" contains IERC4626 yield-bearing tokens (e.g., waDAI).
     * @param pool Address of the liquidity pool
     * @param exactBptAmountIn Exact amount of pool tokens provided for the query
     * @param userData Additional (optional) data required for the query
     * @return underlyingAmountsOut Expected amounts of tokens to receive, sorted in token registration order of
     * wrapped tokens in the pool
     */
    function queryRemoveLiquidityProportionalFromERC4626Pool(
        address pool,
        uint256 exactBptAmountIn,
        bytes memory userData
    ) external returns (uint256[] memory underlyingAmountsOut);

    /***************************************************************************
                                   Nested pools
    ***************************************************************************/

    /**
     * @notice Removes liquidity of a nested pool.
     * @dev A nested pool is one in which one or more tokens are BPTs from another pool (child pool). Since there are
     * multiple pools involved, the token order is not given, so the user must pass the order in which he prefers to
     * receive the token amounts.
     *
     * @param parentPool Address of the highest level pool (which contains BPTs of other pools)
     * @param exactBptAmountIn Exact amount of `parentPool` tokens provided
     * @param tokensOut Output token addresses, sorted by user preference. `tokensOut` array must have all tokens from
     * child pools and all tokens that are not BPTs from the nested pool (parent pool). If not all tokens are informed,
     * balances are not settled and the operation reverts. Tokens that repeat must be informed only once.
     * @param minAmountsOut Minimum amounts of each outgoing underlying token, sorted by token address
     * @param userData Additional (optional) data required for the operation
     * @return amountsOut Actual amounts of tokens received, parallel to `tokensOut`
     */
    function removeLiquidityProportionalFromNestedPools(
        address parentPool,
        uint256 exactBptAmountIn,
        address[] memory tokensOut,
        uint256[] memory minAmountsOut,
        bytes memory userData
    ) external returns (uint256[] memory amountsOut);
}
