// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

/// @notice Errors are declared inside an interface (namespace) to improve DX with Typechain.
interface ICompositeLiquidityRouterErrors {
    /**
     * @notice The actual result of the liquidity removal operation does not match the expected set of tokens.
     * @param actualTokensOut The set of tokens derived from pool traversal
     * @param expectedTokensOut The set of tokens supplied by the user
     */
    error WrongTokensOut(address[] actualTokensOut, address[] expectedTokensOut);

    /**
     * @notice The `tokensIn` array contains a duplicate token.
     * @dev Note that it's technically possible to have duplicate tokens with 0 amounts, as those are ignored.
     * @param duplicateToken The address of the duplicate token
     */
    error DuplicateTokenIn(address duplicateToken);

    /**
     * @notice A token was to be unwrapped, but the amount available was too small for the Vault buffer to unwrap it.
     * @dev Raised by the proportional removal paths, from an ERC4626 pool and from a nested pool alike. The amount is
     * the pool's rather than the caller's: it is that token's share of the burned pool tokens. The Vault rejects wrap
     * and unwrap amounts below its minimum wrap amount, applying that minimum both to the wrapped amount given and to
     * the underlying amount calculated, so the smallest acceptable amount is a property of the wrapper and not a
     * constant. Since the caller asked for the underlying token, the wrapped token is never delivered in its place:
     * the operation fails instead, and reports the token and the amount that was available. It reports what was
     * available rather than what would have been enough, deliberately: the latter inverts the wrapper's redeem curve
     * and cannot be computed here. Query the operation to find a burn that works.
     *
     * Note that a nested traversal can reach the same wrapper at more than one level, and each occurrence is unwrapped
     * on its own and has to clear the Vault's minimum on its own. The amount reported is that occurrence's, which is
     * not necessarily everything the caller was owed in that token.
     *
     * @param wrappedToken The ERC4626 token that could not be unwrapped
     * @param wrappedAmount The amount of `wrappedToken` the pool returned for this token
     */
    error UnwrapAmountTooSmall(address wrappedToken, uint256 wrappedAmount);

    /**
     * @notice A token was to be wrapped, but the amount the pool required was too small for the Vault buffer to wrap.
     * @dev Raised by the proportional add path. The counterpart of `UnwrapAmountTooSmall`, and the amount means the
     * mirror of what it means there: not the amount that was available, but the amount the pool requires for the
     * requested pool token output. The Vault's minimum applies both to that wrapped amount and to the underlying
     * amount it costs, so the smallest acceptable amount is again a property of the wrapper rather than a constant,
     * and it is not the same amount the removal paths accept for the same wrapper.
     *
     * The caller supplies the underlying token, so nothing else is charged in its place and nothing beyond
     * `maxAmountsIn` is taken: the operation fails and leaves the caller holding their own tokens. Requesting more
     * pool tokens raises the required amount, and clearing the wrap flag for this token pays it wrapped instead.
     *
     * @param wrappedToken The ERC4626 token that could not be wrapped
     * @param wrappedAmount The amount of `wrappedToken` the pool requires for this token
     */
    error RequiredWrapAmountTooSmall(address wrappedToken, uint256 wrappedAmount);
}
