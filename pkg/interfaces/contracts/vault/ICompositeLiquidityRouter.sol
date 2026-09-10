// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { ICompositeLiquidityRouterErrors } from "./ICompositeLiquidityRouterErrors.sol";

/**
 * @notice The composite liquidity router supports add/remove liquidity operations on ERC4626 and nested pools.
 * @dev This contract allow interacting with ERC4626 Pools (which contain wrapped ERC4626 tokens) using only underlying
 * standard tokens. For instance, with `addLiquidityUnbalancedToERC4626Pool` it is possible to add liquidity to an
 * ERC4626 Pool with [waDAI, waUSDC], using only DAI, only USDC, or an arbitrary amount of both. If the ERC4626 buffers
 * in the Vault have liquidity, these will be used to avoid wrapping/unwrapping through the wrapped token interface,
 * saving gas.
 *
 * For instance, adding only DAI to the pool above (and assuming a waDAI buffer with enough liquidity), would pull in
 * the DAI from the user, swap it for waDAI in the internal Vault buffer, and deposit the waDAI into the ERC4626 pool:
 * 1) without having to do any expensive ERC4626 wrapping operations; and
 * 2) without requiring the user to construct a batch operation containing the buffer swap.
 */
interface ICompositeLiquidityRouter is ICompositeLiquidityRouterErrors {
    /***************************************************************************
                                   ERC4626 Pools
    ***************************************************************************/

    /**
     * @notice Add arbitrary amounts of tokens to an ERC4626 pool through the buffer.
     * @dev An "ERC4626 pool" contains IERC4626 yield-bearing tokens (e.g., waDAI). Ensure that any buffers associated
     * with the wrapped tokens in the ERC4626 pool have been initialized before initializing or adding liquidity to
     * the "parent" pool, and also make sure limits are set properly.
     *
     * @param pool Address of the liquidity pool
     * @param wrapUnderlying Flags indicating whether the corresponding token should be wrapped or used as an ERC20
     * @param exactAmountsIn Exact amounts of underlying/wrapped tokens in, sorted in token registration order
     * @param minBptAmountOut Minimum amount of pool tokens to be received
     * @param wethIsEth If true, incoming ETH will be wrapped to WETH and outgoing WETH will be unwrapped to ETH
     * @param userData Additional (optional) data required for adding liquidity
     * @return bptAmountOut Actual amount of pool tokens received
     */
    function addLiquidityUnbalancedToERC4626Pool(
        address pool,
        bool[] memory wrapUnderlying,
        uint256[] memory exactAmountsIn,
        uint256 minBptAmountOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable returns (uint256 bptAmountOut);

    /**
     * @notice Queries an `addLiquidityUnbalancedToERC4626Pool` operation without actually executing it.
     * @dev An "ERC4626 pool" contains IERC4626 yield-bearing tokens (e.g., waDAI).
     * @param pool Address of the liquidity pool
     * @param wrapUnderlying Flags indicating whether the corresponding token should be wrapped or used as an ERC20
     * @param exactAmountsIn Exact amounts of underlying/wrapped tokens in, sorted in token registration order
     * @param sender The sender passed to the operation. It can influence results (e.g., with user-dependent hooks)
     * @param userData Additional (optional) data required for the query
     * @return bptAmountOut Expected amount of pool tokens to receive
     */
    function queryAddLiquidityUnbalancedToERC4626Pool(
        address pool,
        bool[] memory wrapUnderlying,
        uint256[] memory exactAmountsIn,
        address sender,
        bytes memory userData
    ) external returns (uint256 bptAmountOut);

    /**
     * @notice Add proportional amounts of tokens to an ERC4626 pool through the buffer.
     * @dev An "ERC4626 pool" contains IERC4626 yield-bearing tokens (e.g., waDAI). Ensure that any buffers associated
     * with the wrapped tokens in the ERC4626 pool have been initialized before initializing or adding liquidity to
     * the "parent" pool, and also make sure limits are set properly. `maxAmountsIn` is denominated in the tokens the
     * sender pays: the underlying token (e.g., DAI) wherever `wrapUnderlying` is set, and the wrapped token
     * (e.g., waDAI) elsewhere. The returned `amountsIn` use the same denominations, so a query result can be passed
     * back in as limits.
     *
     * Wherever `wrapUnderlying` is set, the pool fixes the amount to wrap, so the caller reaches it only through
     * `exactBptAmountOut`. If the Vault buffer will not wrap that amount, the call reverts with
     * `RequiredWrapAmountTooSmall`.
     *
     * @param pool Address of the liquidity pool
     * @param wrapUnderlying Flags indicating whether the corresponding token should be wrapped or used as an ERC20
     * @param maxAmountsIn Maximum amounts of underlying/wrapped tokens in, sorted in token registration order
     * @param exactBptAmountOut Exact amount of pool tokens to be received
     * @param wethIsEth If true, incoming ETH will be wrapped to WETH and outgoing WETH will be unwrapped to ETH
     * @param userData Additional (optional) data required for adding liquidity
     * @return amountsIn Actual amounts of tokens added to the pool
     */
    function addLiquidityProportionalToERC4626Pool(
        address pool,
        bool[] memory wrapUnderlying,
        uint256[] memory maxAmountsIn,
        uint256 exactBptAmountOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable returns (uint256[] memory amountsIn);

    /**
     * @notice Queries an `addLiquidityProportionalToERC4626Pool` operation without actually executing it.
     * @dev An "ERC4626 pool" contains IERC4626 yield-bearing tokens (e.g., waDAI). This is a quote, not a simulation:
     * it passes unlimited maximums, and does not use buffer liquidity. See `addLiquidityProportionalToERC4626Pool`.
     *
     * @param pool Address of the liquidity pool
     * @param wrapUnderlying Flags indicating whether the corresponding token should be wrapped or used as an ERC20
     * @param exactBptAmountOut Exact amount of pool tokens to be received
     * @param sender The sender passed to the operation. It can influence results (e.g., with user-dependent hooks)
     * @param userData Additional (optional) data required for the query
     * @return amountsIn Expected amounts of tokens added to the pool
     */
    function queryAddLiquidityProportionalToERC4626Pool(
        address pool,
        bool[] memory wrapUnderlying,
        uint256 exactBptAmountOut,
        address sender,
        bytes memory userData
    ) external returns (uint256[] memory amountsIn);

    /**
     * @notice Remove proportional amounts of tokens from an ERC4626 pool, burning an exact pool token amount.
     * @dev An "ERC4626 pool" contains IERC4626 yield-bearing tokens (e.g., waDAI). `minAmountsOut` is denominated in
     * the tokens the sender receives: the underlying token (e.g., DAI) wherever `unwrapWrapped` is set, and the
     * wrapped token (e.g., waDAI) elsewhere. The returned `amountsOut` use the same denominations, so a query result
     * can be passed back in as limits.
     *
     * Wherever `unwrapWrapped` is set, the pool fixes the amount to unwrap: it is that token's share of the burned
     * pool tokens. If the Vault buffer will not unwrap that amount, the call reverts with `UnwrapAmountTooSmall`. A
     * share of exactly zero is not that case; it is returned as zero of the underlying token.
     *
     * This function always takes the ordinary removal path, and never a recovery-mode withdrawal. To withdraw from a
     * paused pool, enable Recovery Mode if it is not already on (`IVaultAdmin.enableRecoveryMode`), call
     * `Router.removeLiquidityRecovery` for the pool's registered tokens, then redeem the ERC4626 shares against each
     * wrapper. That path takes no `wethIsEth`, so it pays WETH.
     *
     * @param pool Address of the liquidity pool
     * @param unwrapWrapped Flags indicating whether the corresponding token should be unwrapped or used as an ERC20
     * @param exactBptAmountIn Exact amount of pool tokens provided
     * @param minAmountsOut Minimum amounts of underlying/wrapped tokens out, sorted in token registration order
     * @param wethIsEth If true, incoming ETH will be wrapped to WETH and outgoing WETH will be unwrapped to ETH
     * @param userData Additional (optional) data required for removing liquidity
     * @return amountsOut Actual amounts of underlying/wrapped tokens received
     */
    function removeLiquidityProportionalFromERC4626Pool(
        address pool,
        bool[] memory unwrapWrapped,
        uint256 exactBptAmountIn,
        uint256[] memory minAmountsOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable returns (uint256[] memory amountsOut);

    /**
     * @notice Queries a `removeLiquidityProportionalFromERC4626Pool` operation without actually executing it.
     * @dev An "ERC4626 pool" contains IERC4626 yield-bearing tokens (e.g., waDAI). This is a quote, not a simulation:
     * it passes zero limits, and does not use buffer liquidity. See `removeLiquidityProportionalFromERC4626Pool`.
     *
     * @param pool Address of the liquidity pool
     * @param unwrapWrapped Flags indicating whether the corresponding token should be unwrapped or used as an ERC20
     * @param exactBptAmountIn Exact amount of pool tokens provided for the query
     * @param sender The sender passed to the operation. It can influence results (e.g., with user-dependent hooks)
     * @param userData Additional (optional) data required for the query
     * @return amountsOut Expected amounts of underlying/wrapped tokens to receive
     */
    function queryRemoveLiquidityProportionalFromERC4626Pool(
        address pool,
        bool[] memory unwrapWrapped,
        uint256 exactBptAmountIn,
        address sender,
        bytes memory userData
    ) external returns (uint256[] memory amountsOut);

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
     * NB: Pools with "overlapping" tokens (i.e., both the parent and a child pool contain one or more of the tokens in
     * `tokensIn`), are not supported! The gas cost to explicitly detect this rare edge case would be prohibitive, so
     * behavior in this case is undefined.
     *
     * @param parentPool The address of the parent pool (which contains BPTs of other pools)
     * @param tokensIn An array with all tokens from the child pools, and all non-BPT parent tokens, in arbitrary order
     * @param exactAmountsIn An array with the amountIn of each token, sorted in the same order as tokensIn
     * @param tokensToWrap A list of ERC4626 tokens which should be wrapped if encountered during pool traversal
     * @param minBptAmountOut Expected minimum amount of parent pool tokens to receive
     * @param wethIsEth If true, incoming ETH will be wrapped to WETH and outgoing WETH will be unwrapped to ETH
     * @param userData Additional (optional) data required for the operation
     * @return bptAmountOut The actual amount of parent pool tokens received
     */
    function addLiquidityUnbalancedNestedPool(
        address parentPool,
        address[] memory tokensIn,
        uint256[] memory exactAmountsIn,
        address[] memory tokensToWrap,
        uint256 minBptAmountOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable returns (uint256 bptAmountOut);

    /**
     * @notice Queries an `addLiquidityUnbalancedNestedPool` operation without actually executing it.
     * @param parentPool The address of the parent pool (which contains BPTs of other pools)
     * @param tokensIn An array with all tokens from the child pools, and all non-BPT parent tokens, in arbitrary order
     * @param exactAmountsIn An array with the amountIn of each token, sorted in the same order as tokensIn
     * @param tokensToWrap A list of ERC4626 tokens which should be wrapped if encountered during pool traversal
     * @param sender The sender passed to the operation. It can influence results (e.g., with user-dependent hooks)
     * @param userData Additional (optional) data required for the operation
     * @return bptAmountOut The actual amount of parent pool tokens received
     */
    function queryAddLiquidityUnbalancedNestedPool(
        address parentPool,
        address[] memory tokensIn,
        uint256[] memory exactAmountsIn,
        address[] memory tokensToWrap,
        address sender,
        bytes memory userData
    ) external returns (uint256 bptAmountOut);

    /**
     * @notice Removes liquidity from a nested pool.
     * @dev A nested pool is one in which one or more tokens are BPTs from another pool (child pool). Since there are
     * multiple pools involved, the token order is not well-defined, and must be specified by the caller. If the parent
     * or nested pools contain ERC4626 tokens that appear in the `tokensToUnwrap` list, they will be unwrapped and
     * their underlying tokens sent to the output. Otherwise, they will be treated as regular tokens.
     *
     * For any token in `tokensToUnwrap`, the pool fixes the amount to unwrap: it is that token's share of the burned
     * pool tokens, at the level of the traversal where the token is found. If the Vault buffer will not unwrap that
     * amount, the call reverts with `UnwrapAmountTooSmall`. A share of exactly zero is not that case; it is returned
     * as zero of the underlying token.
     *
     * This function always takes the ordinary removal path, for the parent pool and every child pool, and never a
     * recovery-mode withdrawal. To withdraw where a pool is paused, unwind one level at a time, taking for each pool
     * whichever path its own state allows: `Router.removeLiquidityProportional`, or `Router.removeLiquidityRecovery`
     * preceded by `IVaultAdmin.enableRecoveryMode`. The parent pays child pool BPT as an ordinary ERC20; redeem any
     * ERC4626 shares against their wrappers at the end.
     *
     * @param parentPool The address of the parent pool (which contains BPTs of other pools)
     * @param exactBptAmountIn The exact amount of `parentPool` tokens provided
     * @param tokensOut An array with all tokens from the child pools, and all non-BPT parent tokens, in arbitrary order
     * @param minAmountsOut An array with the minimum amountOut of each token, sorted in the same order as tokensOut
     * @param tokensToUnwrap A list of ERC4626 tokens which should be unwrapped if encountered during pool traversal
     * @param wethIsEth If true, incoming ETH will be wrapped to WETH and outgoing WETH will be unwrapped to ETH
     * @param userData Additional (optional) data required for the operation
     * @return amountsOut An array with the actual amountOut of each token, sorted in the same order as tokensOut
     */
    function removeLiquidityProportionalNestedPool(
        address parentPool,
        uint256 exactBptAmountIn,
        address[] memory tokensOut,
        uint256[] memory minAmountsOut,
        address[] memory tokensToUnwrap,
        bool wethIsEth,
        bytes memory userData
    ) external payable returns (uint256[] memory amountsOut);

    /**
     * @notice Queries an `removeLiquidityProportionalNestedPool` operation without actually executing it.
     * @dev This is a quote, not a simulation: it passes zero minimums, and does not use buffer liquidity.
     * See `removeLiquidityProportionalNestedPool`.
     *
     * @param parentPool The address of the parent pool (which contains BPTs of other pools)
     * @param exactBptAmountIn The exact amount of `parentPool` tokens provided
     * @param tokensOut An array with all tokens from the child pools, and all non-BPT parent tokens, in arbitrary order
     * @param tokensToUnwrap A list of ERC4626 tokens which should be unwrapped if encountered during pool traversal
     * @param sender The sender passed to the operation. It can influence results (e.g., with user-dependent hooks)
     * @param userData Additional (optional) data required for the operation
     * @return amountsOut An array with the expected amountOut of each token, sorted in the same order as tokensOut
     */
    function queryRemoveLiquidityProportionalNestedPool(
        address parentPool,
        uint256 exactBptAmountIn,
        address[] memory tokensOut,
        address[] memory tokensToUnwrap,
        address sender,
        bytes memory userData
    ) external returns (uint256[] memory amountsOut);
}
