// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { SignedMath } from "@openzeppelin/contracts/utils/math/SignedMath.sol";

import { WordCodec } from "../../contracts/helpers/WordCodec.sol";

contract WordCodecTest is Test {
    function testEncodeUint255Bits__Fuzz(uint256 input) external pure {
        vm.assume(input < (1 << (255 - 1)));

        bytes32 data = WordCodec.encodeUint(input, 0, 255);
        uint256 decoded = WordCodec.decodeUint(data, 0, 255);

        assertEq(decoded, input);
    }

    function testEncodeUintMultiBits__Fuzz(uint256 input, uint8 bits, uint256 offset) external pure {
        (input, bits, offset) = _getAdjustedValues(input, bits, offset);

        bytes32 data = WordCodec.encodeUint(input, offset, bits);
        uint256 decoded = WordCodec.decodeUint(data, offset, bits);

        assertEq(decoded, input);
    }

    function testEncodeUintOtherBitsFree__Fuzz(uint256 input, uint8 bits, uint256 offset) external pure {
        (input, bits, offset) = _getAdjustedValues(input, bits, offset);

        bytes32 data = WordCodec.encodeUint(input, offset, bits);
        bytes32 mask = bytes32(((1 << bits) - 1) << offset);
        assertEq(data & ~mask, bytes32(0));
    }

    function _getAdjustedValues(
        uint256 input,
        uint8 bits,
        uint256 offset
    ) private pure returns (uint256, uint8, uint256) {
        vm.assume(bits > 0);
        vm.assume(input < (1 << (255 - 1)));

        input = input & ((1 << bits) - 1);
        if (bits < 255) {
            offset = offset % (255 - bits);
        } else {
            offset = 0;
        }

        return (input, bits, offset);
    }

    function testInsertUint__Fuzz(bytes32 word, uint256 value, uint256 offset, uint256 bitLength) external {
        if (offset >= 256 || !(bitLength >= 1 && bitLength <= Math.min(255, 256 - offset))) {
            vm.expectRevert(WordCodec.OutOfBounds.selector);
            WordCodec.insertUint(word, value, offset, bitLength);
        } else if (value >> bitLength != 0) {
            vm.expectRevert(WordCodec.CodecOverflow.selector);
            WordCodec.insertUint(word, value, offset, bitLength);
        } else {
            uint256 mask = (1 << bitLength) - 1;
            bytes32 clearedWord = bytes32(uint256(word) & ~(mask << offset));
            bytes32 referenceInsertUint = clearedWord | bytes32(value << offset);

            bytes32 insertUint = WordCodec.insertUint(word, value, offset, bitLength);

            assertEq(insertUint, referenceInsertUint);
        }
    }

    function testInsertInt__Fuzz(bytes32 word, int256 value, uint256 offset, uint256 bitLength) external {
        if (offset >= 256 || !(bitLength >= 1 && bitLength <= Math.min(255, 256 - offset))) {
            vm.expectRevert(WordCodec.OutOfBounds.selector);
            WordCodec.insertInt(word, value, offset, bitLength);
            return;
        } else if (value >= 0 ? value >> (bitLength - 1) != 0 : SignedMath.abs(value + 1) >> (bitLength - 1) != 0) {
            vm.expectRevert(WordCodec.CodecOverflow.selector);
            WordCodec.insertInt(word, value, offset, bitLength);
        } else {
            uint256 mask = (1 << bitLength) - 1;
            bytes32 clearedWord = bytes32(uint256(word) & ~(mask << offset));
            bytes32 referenceInsertInt = clearedWord | bytes32((uint256(value) & mask) << offset);

            bytes32 insertInt = WordCodec.insertInt(word, value, offset, bitLength);

            assertEq(insertInt, referenceInsertInt);
        }
    }

    function testInsertBool__Fuzz(bytes32 word, bool value, uint256 offset) external pure {
        bytes32 clearedWord = bytes32(uint256(word) & ~(1 << offset));
        bytes32 referenceInsertBool = clearedWord | bytes32(uint256(value ? 1 : 0) << offset);

        bytes32 insertBool = WordCodec.insertBool(word, value, offset);

        assertEq(insertBool, referenceInsertBool);
    }

    function testDecodeUint__Fuzz(bytes32 word, uint256 offset, uint8 bitLength) external pure {
        vm.assume(bitLength > 0);
        uint256 referenceDecodeUint = uint256(word >> offset) & ((1 << bitLength) - 1);
        uint256 decodeUint = WordCodec.decodeUint(word, offset, bitLength);

        assertEq(decodeUint, referenceDecodeUint);
    }

    function testDecodeInt__Fuzz(bytes32 word, uint256 offset, uint8 bitLength) external pure {
        vm.assume(bitLength > 0);
        int256 maxInt = int256((1 << (bitLength - 1)) - 1);
        uint256 mask = (1 << bitLength) - 1;
        int256 value = int256(uint256(word >> offset) & mask);
        int256 referenceDecodeInt = value > maxInt ? (value | int256(~mask)) : value;

        int256 decodeInt = WordCodec.decodeInt(word, offset, bitLength);

        assertEq(decodeInt, referenceDecodeInt);
    }

    function testDecodeBool__Fuzz(bytes32 word, uint256 offset) external pure {
        bool referenceDecodeBool = (uint256(word >> offset) & 1) == 1;
        bool decodeBool = WordCodec.decodeBool(word, offset);

        assertEq(decodeBool, referenceDecodeBool);
    }
}
