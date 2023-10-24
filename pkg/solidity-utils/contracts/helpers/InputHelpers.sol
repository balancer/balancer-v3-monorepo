// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

library InputHelpers {
    /// @dev Arrays passed to a function and intended to be parallel have different lengths.
    error InputLengthMismatch();

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
}
