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
     * Here the caller names each amount, so an amount the Vault buffer will not wrap is reported as the Vault's own
     * `WrapAmountTooSmall`, naming the token, and the remedy is to name a larger amount. The proportional operations
     * report that condition differently only because there the amount comes from the pool and the caller cannot set
     * it directly.
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
     * the "parent" pool, and also make sure limits are set properly. Note that `maxAmountsIn` is denominated in the
     * tokens the sender actually pays, and not in the pool's own tokens: the underlying token (e.g., DAI) wherever
     * `wrapUnderlying` is set, and the wrapped token (e.g., waDAI) elsewhere. These are the same denominations as the
     * returned `amountsIn`, so a limit can be derived directly from a query result.
     *
     * Wherever `wrapUnderlying` is set, the amount wrapped is what the pool requires for `exactBptAmountOut`, and not
     * an amount the caller chose. Where the Vault buffer will not wrap it the call reverts with
     * `RequiredWrapAmountTooSmall`, which names the token and the amount, and nothing else is charged in its place.
     * The buffer applies its minimum to the wrapped amount it is given and again to the underlying amount it
     * calculates, testing the caller's limit between the two, so a limit the leg cannot meet is reported as
     * `SwapLimit` ahead of the second of those but not of the first. A failed call leaves the sender holding their own
     * tokens. Requesting more pool tokens always raises the required amount, so it clears this for any wrapper as long
     * as `maxAmountsIn` covers the larger cost; clearing `wrapUnderlying` for that token pays it wrapped instead.
     * Requesting no pool tokens at all makes no buffer call and charges nothing.
     *
     * Note that each token's whole `maxAmountsIn` entry is taken from the sender up front and the unused part is
     * returned at the end, so the sender must hold and have approved the limit rather than the eventual cost.
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
     * @dev An "ERC4626 pool" contains IERC4626 yield-bearing tokens (e.g., waDAI). Like the operation it quotes, it
     * reverts `RequiredWrapAmountTooSmall` for a token whose required amount is too small to wrap. It is a quote and
     * not a simulation: it passes unlimited maximums, so it will not report a limit the caller would have hit, and it
     * returns the buffer's calculated amount without exercising the buffer's liquidity, so it cannot report a failure
     * that arises only where the buffer has to mint through the wrapper itself.
     * See `addLiquidityProportionalToERC4626Pool`.
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
     * @dev An "ERC4626 pool" contains IERC4626 yield-bearing tokens (e.g., waDAI). Note that `minAmountsOut` is
     * denominated in the tokens the sender actually receives, and not in the pool's own tokens: the underlying token
     * (e.g., DAI) wherever `unwrapWrapped` is set, and the wrapped token (e.g., waDAI) elsewhere. These are the same
     * denominations as the returned `amountsOut`, so a limit can be derived directly from a query result.
     *
     * Wherever `unwrapWrapped` is set, the amount unwrapped is that token's share of the burned pool tokens, and not
     * an amount the caller chose. Where the Vault buffer will not unwrap it the call reverts with
     * `UnwrapAmountTooSmall`, which names the token and the amount, and the wrapped token is never delivered in its
     * place. The buffer applies its minimum to the wrapped amount it is given and again to the underlying amount it
     * calculates, testing the caller's limit between the two, so a limit the leg cannot meet is reported as
     * `SwapLimit` ahead of the second of those but not of the first. Clearing `unwrapWrapped` for that
     * token always works and pays it wrapped, as does `Router.removeLiquidityProportional`; burning more pool tokens
     * works only where the pool holds enough of that token for a larger share to clear the buffer's minimum, which
     * is not true of every pool. An amount of exactly zero is not this case: it is returned as zero of the underlying
     * token, and the withdrawal succeeds.
     *
     * This function does not perform recovery-mode withdrawal. The ordinary removal path is always taken, so the
     * call reverts wherever that path would: when the pool or the Vault is paused, when a rate provider or a pool
     * hook fails, or when the burn is small enough that a token's share is below the Vault's minimum trade amount
     * (`TradeAmountTooSmall`); the remedy there is to burn more. Pool hooks apply on this path, so where the pool
     * enables hook-adjusted amounts, the amounts paid are the hook's; `Router.removeLiquidityRecovery` makes no
     * hook calls at all. To withdraw in such a state, put the pool in Recovery Mode if it is not already
     * (`IVaultAdmin.enableRecoveryMode`, which is permissionless while the pool or the Vault is paused), call
     * `Router.removeLiquidityRecovery` for the pool's registered tokens, and redeem the ERC4626 shares directly
     * against each wrapper. Note that the recovery withdrawal takes no `wethIsEth`, so it pays WETH, not ETH.
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
     * @dev An "ERC4626 pool" contains IERC4626 yield-bearing tokens (e.g., waDAI). Like the operation it quotes, this
     * does not perform recovery-mode withdrawal, and it reverts `UnwrapAmountTooSmall` for a token whose share is too
     * small to unwrap. It is a quote and not a simulation: it passes zero limits, so it will not report a limit the
     * caller would have hit, and it returns the buffer's calculated amount without exercising the buffer's liquidity,
     * so it cannot report a failure that arises only where the buffer has to redeem through the wrapper itself.
     * See `removeLiquidityProportionalFromERC4626Pool`.
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
     * Here the caller names each amount, so an amount the Vault buffer will not wrap is reported as the Vault's own
     * `WrapAmountTooSmall`, naming the token, and the remedy is to name a larger amount, or to leave that token out
     * of `tokensToWrap` and pay it wrapped instead. The proportional operations report that condition differently
     * only because there the amount comes from the pool and the caller cannot set it directly.
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
     * For any token in `tokensToUnwrap`, the amount unwrapped is that token's share of the burned pool tokens at the
     * level of the traversal where it is found, and not an amount the caller chose. Where the Vault buffer will not
     * unwrap it the call reverts, and the wrapped token is never delivered in its place: with `UnwrapAmountTooSmall`,
     * which names the token and the amount, and which the proportional removal from an ERC4626 pool raises for the
     * same condition. Leaving that token out of `tokensToUnwrap` always works and pays it wrapped; burning more
     * parent pool tokens works only where the pools hold enough of that token for a larger share to clear the
     * buffer's minimum, which is not true of every pool. An amount of exactly zero is not this case: that token is
     * returned as zero of its underlying token, and the withdrawal succeeds.
     *
     * This function does not perform recovery-mode withdrawal. The ordinary removal path is always taken, for the
     * parent pool and for every child pool, so the call reverts wherever that path would: when any of those pools or
     * the Vault is paused, when a rate provider or a pool hook fails, or when a burn is small enough that a token's
     * share is below the Vault's minimum trade amount (`TradeAmountTooSmall`); the remedy there is to burn more.
     * Each pool's hooks apply on this path, so where a pool enables hook-adjusted amounts, the amounts paid are the
     * hook's; `Router.removeLiquidityRecovery` makes no hook calls at all. To withdraw in such a state, unwind one
     * level at a time, taking for each pool whichever path its own state allows: `Router.removeLiquidityProportional`
     * where the pool is healthy, or `Router.removeLiquidityRecovery` where it is not, preceded by
     * `IVaultAdmin.enableRecoveryMode` if that pool is not in Recovery Mode already (permissionless while it or the
     * Vault is paused). The parent pays child pool BPT as an ordinary ERC20; redeem any ERC4626 shares directly
     * against their wrappers at the end.
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
     * @dev Like the operation it quotes, this does not perform recovery-mode withdrawal, and it reverts
     * `UnwrapAmountTooSmall` for a token whose share is too small to unwrap. It is a quote and not a simulation: it
     * passes zero minimums, so it will not report a limit the caller would have hit, and it returns the buffer's
     * calculated amount without exercising the buffer's liquidity, so it cannot report a failure that arises only
     * where the buffer has to redeem through the wrapper itself.
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
