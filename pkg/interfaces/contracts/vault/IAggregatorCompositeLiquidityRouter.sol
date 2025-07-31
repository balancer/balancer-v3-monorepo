// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { ICompositeLiquidityRouterQueries } from "./ICompositeLiquidityRouterQueries.sol";

/**
 * @notice An aggregator composite liquidity router for liquidity operations on ERC4626 and nested pools.
 * @dev This contract allows interacting with ERC4626 Pools (which contain wrapped ERC4626 tokens) using only standard
 * underlying tokens. For instance, with `addLiquidityUnbalancedToERC4626Pool` it is possible to add liquidity to an
 * ERC4626 Pool with [waDAI, waUSDC], using only DAI, only USDC, or an arbitrary amount of both. If the ERC4626 buffers
 * in the Vault have liquidity, these will be used to avoid wrapping/unwrapping through the wrapped token interface,
 * saving gas.
 *
 * For instance, adding only DAI to the pool above (and assuming a waDAI buffer with enough liquidity), would pull in
 * the DAI from the user, swap it for waDAI in the internal Vault buffer, and deposit the waDAI into the ERC4626 pool:
 * 1) without having to do any expensive ERC4626 wrapping operations; and
 * 2) without requiring the user to construct a batch operation containing the buffer swap.
 *
 * The aggregator composite liquidity router is designed to be called from a contract vs. an EOA through a UI.
 * It uses prepayment instead of permit2, and defines identical functions with the same parameters as
 * `ICompositeLiquidityRouter`, but without support for native ETH wrapping/unwrapping.
 */
interface IAggregatorCompositeLiquidityRouter is ICompositeLiquidityRouterQueries {
    /***************************************************************************
                                   ERC4626 Pools
    ***************************************************************************/

    /**
     * @notice Add arbitrary amounts of tokens to an ERC4626 pool through the buffer.
     * @dev An "ERC4626 pool" contains at least one IERC4626 yield-bearing token (e.g., waDAI). Ensure that any buffers associated
     * with the wrapped tokens in the ERC4626 pool have been initialized before adding liquidity to
     * the "parent" pool, and also make sure limits are set properly.
     *
     * @param pool Address of the liquidity pool
     * @param wrapUnderlying Flags indicating whether the corresponding token should be wrapped or used as an ERC20
     * @param exactAmountsIn Exact amounts of underlying/wrapped tokens in, sorted in token registration order
     * @param minBptAmountOut Minimum amount of pool tokens to be received
     * @param userData Additional (optional) data required for adding liquidity
     * @return bptAmountOut Actual amount of pool tokens received
     */
    function addLiquidityUnbalancedToERC4626Pool(
        address pool,
        bool[] memory wrapUnderlying,
        uint256[] memory exactAmountsIn,
        uint256 minBptAmountOut,
        bytes memory userData
    ) external payable returns (uint256 bptAmountOut);

    /**
     * @notice Add proportional amounts of tokens to an ERC4626 pool through the buffer.
     * @dev An "ERC4626 pool" contains at least one IERC4626 yield-bearing token (e.g., waDAI). Ensure that any buffers associated
     * with the wrapped tokens in the ERC4626 pool have been initialized before adding liquidity to
     * the "ERC4626 pool", and also make sure limits are set properly.
     *
     * @param pool Address of the liquidity pool
     * @param wrapUnderlying Flags indicating whether the corresponding token should be wrapped or used as an ERC20
     * @param maxAmountsIn Maximum amounts of underlying/wrapped tokens in, sorted in token registration order
     * @param exactBptAmountOut Exact amount of pool tokens to be received
     * @param userData Additional (optional) data required for adding liquidity
     * @return amountsIn Actual amounts of tokens added to the pool
     */
    function addLiquidityProportionalToERC4626Pool(
        address pool,
        bool[] memory wrapUnderlying,
        uint256[] memory maxAmountsIn,
        uint256 exactBptAmountOut,
        bytes memory userData
    ) external payable returns (uint256[] memory amountsIn);

    /**
     * @notice Remove proportional amounts of tokens from an ERC4626 pool, burning an exact pool token amount.
     * @dev An "ERC4626 pool" contains at least one IERC4626 yield-bearing token (e.g., waDAI).
     * @param pool Address of the liquidity pool
     * @param unwrapWrapped Flags indicating whether the corresponding token should be unwrapped or used as an ERC20
     * @param exactBptAmountIn Exact amount of pool tokens provided
     * @param minAmountsOut Minimum amounts of each token, sorted in token registration order
     * @param userData Additional (optional) data required for removing liquidity
     * @return amountsOut Actual amounts of tokens received
     */
    function removeLiquidityProportionalFromERC4626Pool(
        address pool,
        bool[] memory unwrapWrapped,
        uint256 exactBptAmountIn,
        uint256[] memory minAmountsOut,
        bytes memory userData
    ) external payable returns (uint256[] memory amountsOut);

    /***************************************************************************
                                   Nested pools
    ***************************************************************************/

    /**
     * @notice Adds liquidity unbalanced to a nested pool.
     * @dev A nested pool is one in which one or more tokens are BPTs from another pool (child pool). Since there are
     * multiple pools involved, the token order is not well-defined, and must be specified by the caller. If the parent
     * or nested pools contain ERC4626 tokens that appear in the `tokensToWrap` list, they will be wrapped and their
     * underlying tokens pulled as input, and expected to appear in `tokensIn`. Otherwise, they will be treated as
     * regular tokens.
     *
     * @param parentPool The address of the parent pool (which contains BPTs of other pools)
     * @param tokensIn An array with all tokens from the child pools, and all non-BPT parent tokens, in arbitrary order
     * @param exactAmountsIn An array with the amountIn of each token, sorted in the same order as tokensIn
     * @param tokensToWrap A list of ERC4626 tokens which should be wrapped if encountered during pool traversal
     * @param minBptAmountOut Expected minimum amount of parent pool tokens to receive
     * @param userData Additional (optional) data required for the operation
     * @return bptAmountOut The actual amount of parent pool tokens received
     */
    function addLiquidityUnbalancedNestedPool(
        address parentPool,
        address[] memory tokensIn,
        uint256[] memory exactAmountsIn,
        address[] memory tokensToWrap,
        uint256 minBptAmountOut,
        bytes memory userData
    ) external payable returns (uint256 bptAmountOut);

    /**
     * @notice Removes liquidity from a nested pool.
     * @dev A nested pool is one in which one or more tokens are BPTs from another pool (child pool). Since there are
     * multiple pools involved, the token order is not well-defined, and must be specified by the caller. If the parent
     * or nested pools contain ERC4626 tokens that appear in the `tokensToUnwrap` list, they will be unwrapped and
     * their underlying tokens sent to the output. Otherwise, they will be treated as regular tokens.
     *
     * @param parentPool The address of the parent pool (which contains BPTs of other pools)
     * @param exactBptAmountIn The exact amount of `parentPool` tokens provided
     * @param tokensOut An array with all tokens from the child pools, and all non-BPT parent tokens, in arbitrary order
     * @param minAmountsOut An array with the minimum amountOut of each token, sorted in the same order as tokensOut
     * @param tokensToUnwrap A list of ERC4626 tokens which should be unwrapped if encountered during pool traversal
     * @param userData Additional (optional) data required for the operation
     * @return amountsOut An array with the actual amountOut of each token, sorted in the same order as tokensOut
     */
    function removeLiquidityProportionalNestedPool(
        address parentPool,
        uint256 exactBptAmountIn,
        address[] memory tokensOut,
        uint256[] memory minAmountsOut,
        address[] memory tokensToUnwrap,
        bytes memory userData
    ) external payable returns (uint256[] memory amountsOut);
}
