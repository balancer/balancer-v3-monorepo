// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

library InputHelpers {
    /// @dev Arrays passed to a function and intended to be parallel have different lengths.
    error InputLengthMismatch();

    /**
     * @dev Input arrays for single token add/remove liquidity operations are expected to have only one non-zero value,
     * corresponding to the token being added or removed. This error results if there are multiple non-zero entries.
     */
    error MultipleNonZeroInputs();

    /**
     * @dev Input arrays for single token add/remove liquidity operations are expected to have one non-zero value,
     * corresponding to the token being added or removed. This error results if all entries are zero.
     */
    error AllZeroInputs();

    /**
     * @dev Tokens are not sorted by address on registration. This is an optimization so that off-chain processes can
     * predict the token order without having to query the Vault. (It is also legacy v2 behavior.)
     */
    error TokensNotSorted();

    function ensureInputLengthMatch(uint256 a, uint256 b) internal pure {
        if (a != b) {
            revert InputLengthMismatch();
        }
    }

    function ensureInputLengthMatch(uint256 a, uint256 b, uint256 c) internal pure {
        if (a != b || b != c) {
            revert InputLengthMismatch();
        }
    }

    // Find the single non-zero input; revert if there is not exactly one such value.
    function getSingleInputIndex(uint256[] memory maxAmountsIn) internal pure returns (uint256 inputIndex) {
        uint256 length = maxAmountsIn.length;
        inputIndex = length;

        for (uint256 i = 0; i < length; ++i) {
            if (maxAmountsIn[i] != 0) {
                if (inputIndex != length) {
                    revert MultipleNonZeroInputs();
                }
                inputIndex = i;
            }
        }

        if (inputIndex >= length) {
            revert AllZeroInputs();
        }

        return inputIndex;
    }

    /**
     * @dev Sort an array of tokens, mutating in place (and also returning them).
     * This assumes the tokens have been (or will be) validated elsewhere for length
     * and non-duplication. All this does is the sorting.
     *
     * A bubble sort should be gas- and bytecode-efficient enough for such small arrays.
     * Could have also done "manual" comparisons for each of the cases, but this is
     * about the same number of operations, and more concise.
     *
     * This is less efficient for larger token count (i.e., above 4), but such pools should
     * be rare. And in any case, sorting is only done on-chain in test code.
     */
    function sortTokens(IERC20[] memory tokens) internal pure returns (IERC20[] memory) {
        for (uint256 i = 0; i < tokens.length - 1; ++i) {
            for (uint256 j = 0; j < tokens.length - i - 1; ++j) {
                if (tokens[j] > tokens[j + 1]) {
                    // Swap if they're out of order.
                    (tokens[j], tokens[j + 1]) = (tokens[j + 1], tokens[j]);
                }
            }
        }

        return tokens;
    }

    /// @dev Ensure an array of tokens is sorted. As above, does not validate length or uniqueness.
    function ensureSortedTokens(IERC20[] memory tokens) internal pure {
        IERC20 previous = tokens[0];

        for (uint256 i = 1; i < tokens.length; ++i) {
            IERC20 current = tokens[i];

            if (previous > current) {
                revert TokensNotSorted();
            }

            previous = current;
        }
    }
}
