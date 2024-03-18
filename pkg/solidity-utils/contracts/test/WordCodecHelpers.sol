// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

library WordCodecHelpers {
    function clearWordAtPosition(
        bytes32 word,
        uint256 offset,
        uint256 bitLength
    ) internal pure returns (bytes32 clearedWord) {
        uint256 mask = (1 << bitLength) - 1;
        clearedWord = bytes32(uint256(word) & ~(mask << offset));
    }

    function isOtherStateUnchanged(
        bytes32 oldPoolState,
        bytes32 newPoolState,
        uint256 offset,
        uint256 bitLength
    ) internal pure returns (bool) {
        bytes32 clearedOldState = clearWordAtPosition(oldPoolState, offset, bitLength);
        bytes32 clearedNewState = clearWordAtPosition(newPoolState, offset, bitLength);

        return clearedNewState == clearedOldState;
    }
}
