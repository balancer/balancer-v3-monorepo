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
     * @notice A token's proportional share was too small for the Vault buffer to unwrap.
     * @dev Raised by the proportional removal paths, where the pool fixes the amount and the caller cannot set it.
     * Burning more pool tokens raises the share; leaving the token unwrapped pays it as the wrapped token instead.
     *
     * @param wrappedToken The ERC4626 token that could not be unwrapped
     * @param wrappedAmount The share of `wrappedToken` the pool returned
     */
    error UnwrapAmountTooSmall(address wrappedToken, uint256 wrappedAmount);

    /**
     * @notice The amount of a token the pool required was too small for the Vault buffer to wrap.
     * @dev Raised by the proportional add path, where the pool fixes the amount and the caller cannot set it.
     * Requesting more pool tokens raises the required amount; clearing the wrap flag pays the wrapped token instead.
     *
     * @param wrappedToken The ERC4626 token that could not be wrapped
     * @param wrappedAmount The amount of `wrappedToken` the pool requires
     */
    error RequiredWrapAmountTooSmall(address wrappedToken, uint256 wrappedAmount);
}
