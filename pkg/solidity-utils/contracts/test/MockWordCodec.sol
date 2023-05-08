// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.7.0;

import "../helpers/WordCodec.sol";
import "../helpers/WordCodecHelpers.sol";

contract MockWordCodec {
    function insertUint(
        bytes32 word,
        uint256 value,
        uint256 offset,
        uint256 bitLength
    ) external pure returns (bytes32) {
        return WordCodec.insertUint(word, value, offset, bitLength);
    }

    function insertInt(
        bytes32 word,
        int256 value,
        uint256 offset,
        uint256 bitLength
    ) external pure returns (bytes32) {
        return WordCodec.insertInt(word, value, offset, bitLength);
    }

    function encodeUint(
        uint256 value,
        uint256 offset,
        uint256 bitLength
    ) external pure returns (bytes32) {
        return WordCodec.encodeUint(value, offset, bitLength);
    }

    function encodeInt(
        int256 value,
        uint256 offset,
        uint256 bitLength
    ) external pure returns (bytes32) {
        return WordCodec.encodeInt(value, offset, bitLength);
    }

    function decodeUint(
        bytes32 value,
        uint256 offset,
        uint256 bitLength
    ) external pure returns (uint256) {
        return WordCodec.decodeUint(value, offset, bitLength);
    }

    function decodeInt(
        bytes32 value,
        uint256 offset,
        uint256 bitLength
    ) external pure returns (int256) {
        return WordCodec.decodeInt(value, offset, bitLength);
    }

    function clearWordAtPosition(
        bytes32 word,
        uint256 offset,
        uint256 bitLength
    ) external pure returns (bytes32) {
        return WordCodecHelpers.clearWordAtPosition(word, offset, bitLength);
    }

    function isOtherStateUnchanged(
        bytes32 oldPoolState,
        bytes32 newPoolState,
        uint256 offset,
        uint256 bitLength
    ) external pure returns (bool) {
        return WordCodecHelpers.isOtherStateUnchanged(oldPoolState, newPoolState, offset, bitLength);
    }
}
