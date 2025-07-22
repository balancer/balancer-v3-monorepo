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
}
