// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { SignedMath } from "@openzeppelin/contracts/utils/math/SignedMath.sol";

/**
 * @dev Library for encoding and decoding values stored inside a 256 bit word. Typically used to pack multiple values in
 * a single storage slot, saving gas by performing less storage accesses.
 *
 * Each value is defined by its size and the least significant bit in the word, also known as offset. For example, two
 * 128 bit values may be encoded in a word by assigning one an offset of 0, and the other an offset of 128.
 *
 * We could use Solidity structs to pack values together in a single storage slot instead of relying on a custom and
 * error-prone library, but unfortunately Solidity only allows for structs to live in either storage, calldata or
 * memory. Because a memory struct uses not just memory but also a slot in the stack (to store its memory location),
 * using memory for word-sized values (i.e. of 256 bits or less) is strictly less gas performant, and doesn't even
 * prevent stack-too-deep issues. This is compounded by the fact that Balancer contracts typically are memory-intensive,
 * and the cost of accessing memory increases quadratically with the number of allocated words. Manual packing and
 * unpacking is therefore the preferred approach.
 */
library WordCodec {
    using Math for uint256;
    using SignedMath for int256;

    // solhint-disable no-inline-assembly

    /// @dev Function called with an invalid value.
    error CodecOverflow();

    /// @dev Function called with an invalid bitLength or offset.
    error OutOfBounds();

    /***************************************************************************
                                 In-place Insertion
    ***************************************************************************/

    /**
     * @dev Inserts an unsigned integer of bitLength, shifted by an offset, into a 256 bit word,
     * replacing the old value. Returns the new word.
     */
    function insertUint(
        bytes32 word,
        uint256 value,
        uint256 offset,
        uint256 bitLength
    ) internal pure returns (bytes32 result) {
        _validateEncodingParams(value, offset, bitLength);
        // Equivalent to:
        // uint256 mask = (1 << bitLength) - 1;
        // bytes32 clearedWord = bytes32(uint256(word) & ~(mask << offset));
        // result = clearedWord | bytes32(value << offset);
        assembly {
            let mask := sub(shl(bitLength, 1), 1)
            let clearedWord := and(word, not(shl(offset, mask)))
            result := or(clearedWord, shl(offset, value))
        }
    }

    /**
     * @dev Inserts an address (160 bits), shifted by an offset, into a 256 bit word,
     * replacing the old value. Returns the new word.
     */
    function insertAddress(bytes32 word, address value, uint256 offset) internal pure returns (bytes32 result) {
        uint256 addressBitLength = 160;
        _validateEncodingParams(uint256(uint160(value)), offset, addressBitLength);
        // Equivalent to:
        // uint256 mask = (1 << bitLength) - 1;
        // bytes32 clearedWord = bytes32(uint256(word) & ~(mask << offset));
        // result = clearedWord | bytes32(value << offset);
        assembly {
            let mask := sub(shl(addressBitLength, 1), 1)
            let clearedWord := and(word, not(shl(offset, mask)))
            result := or(clearedWord, shl(offset, value))
        }
    }

    /**
     * @dev Inserts a signed integer shifted by an offset into a 256 bit word, replacing the old value. Returns
     * the new word.
     *
     * Assumes `value` can be represented using `bitLength` bits.
     */
    function insertInt(bytes32 word, int256 value, uint256 offset, uint256 bitLength) internal pure returns (bytes32) {
        _validateEncodingParams(value, offset, bitLength);

        uint256 mask = (1 << bitLength) - 1;
        bytes32 clearedWord = bytes32(uint256(word) & ~(mask << offset));
        // Integer values need masking to remove the upper bits of negative values.
        return clearedWord | bytes32((uint256(value) & mask) << offset);
    }

    /***************************************************************************
                                      Encoding
    ***************************************************************************/

    /**
     * @dev Encodes an unsigned integer shifted by an offset. Ensures value fits within
     * `bitLength` bits.
     *
     * The return value can be ORed bitwise with other encoded values to form a 256 bit word.
     */
    function encodeUint(uint256 value, uint256 offset, uint256 bitLength) internal pure returns (bytes32) {
        _validateEncodingParams(value, offset, bitLength);

        return bytes32(value << offset);
    }

    /**
     * @dev Encodes a signed integer shifted by an offset.
     *
     * The return value can be ORed bitwise with other encoded values to form a 256 bit word.
     */
    function encodeInt(int256 value, uint256 offset, uint256 bitLength) internal pure returns (bytes32) {
        _validateEncodingParams(value, offset, bitLength);

        uint256 mask = (1 << bitLength) - 1;
        // Integer values need masking to remove the upper bits of negative values.
        return bytes32((uint256(value) & mask) << offset);
    }

    /***************************************************************************
                                      Decoding
    ***************************************************************************/

    /// @dev Decodes and returns an unsigned integer with `bitLength` bits, shifted by an offset, from a 256 bit word.
    function decodeUint(bytes32 word, uint256 offset, uint256 bitLength) internal pure returns (uint256 result) {
        // Equivalent to:
        // result = uint256(word >> offset) & ((1 << bitLength) - 1);
        assembly {
            result := and(shr(offset, word), sub(shl(bitLength, 1), 1))
        }
    }

    /// @dev Decodes and returns a signed integer with `bitLength` bits, shifted by an offset, from a 256 bit word.
    function decodeInt(bytes32 word, uint256 offset, uint256 bitLength) internal pure returns (int256 result) {
        int256 maxInt = int256((1 << (bitLength - 1)) - 1);
        uint256 mask = (1 << bitLength) - 1;

        int256 value = int256(uint256(word >> offset) & mask);
        // In case the decoded value is greater than the max positive integer that can be represented with bitLength
        // bits, we know it was originally a negative integer. Therefore, we mask it to restore the sign in the 256 bit
        // representation.
        //
        // Equivalent to:
        // result = value > maxInt ? (value | int256(~mask)) : value;
        assembly {
            result := or(mul(gt(value, maxInt), not(mask)), value)
        }
    }

    /// @dev Decodes and returns an address (160 bits), shifted by an offset, from a 256 bit word.
    function decodeAddress(bytes32 word, uint256 offset) internal pure returns (address result) {
        // Equivalent to:
        // result = address(word >> offset) & ((1 << bitLength) - 1);
        assembly {
            result := and(shr(offset, word), sub(shl(160, 1), 1))
        }
    }

    /***************************************************************************
                                    Special Cases
    ***************************************************************************/

    /// @dev Decodes and returns a boolean shifted by an offset from a 256 bit word.
    function decodeBool(bytes32 word, uint256 offset) internal pure returns (bool result) {
        // Equivalent to:
        // result = (uint256(word >> offset) & 1) == 1;
        assembly {
            result := and(shr(offset, word), 1)
        }
    }

    /**
     * @dev Inserts a boolean value shifted by an offset into a 256 bit word, replacing the old value.
     * Returns the new word.
     */
    function insertBool(bytes32 word, bool value, uint256 offset) internal pure returns (bytes32 result) {
        // Equivalent to:
        // bytes32 clearedWord = bytes32(uint256(word) & ~(1 << offset));
        // bytes32 referenceInsertBool = clearedWord | bytes32(uint256(value ? 1 : 0) << offset);
        assembly {
            let clearedWord := and(word, not(shl(offset, 1)))
            result := or(clearedWord, shl(offset, value))
        }
    }

    /***************************************************************************
                                     Helpers
    ***************************************************************************/

    function _validateEncodingParams(uint256 value, uint256 offset, uint256 bitLength) private pure {
        if (offset >= 256) {
            revert OutOfBounds();
        }
        // We never accept 256 bit values (which would make the codec pointless), and the larger the offset the smaller
        // the maximum bit length.
        if (!(bitLength >= 1 && bitLength <= Math.min(255, 256 - offset))) {
            revert OutOfBounds();
        }

        // Testing unsigned values for size is straightforward: their upper bits must be cleared.
        if (value >> bitLength != 0) {
            revert CodecOverflow();
        }
    }

    function _validateEncodingParams(int256 value, uint256 offset, uint256 bitLength) private pure {
        if (offset >= 256) {
            revert OutOfBounds();
        }
        // We never accept 256 bit values (which would make the codec pointless), and the larger the offset the smaller
        // the maximum bit length.
        if (!(bitLength >= 1 && bitLength <= Math.min(255, 256 - offset))) {
            revert OutOfBounds();
        }

        // Testing signed values for size is a bit more involved.
        if (value >= 0) {
            // For positive values, we can simply check that the upper bits are clear. Notice we remove one bit from the
            // length for the sign bit.
            if (value >> (bitLength - 1) != 0) {
                revert CodecOverflow();
            }
        } else {
            // Negative values can receive the same treatment by making them positive, with the caveat that the range
            // for negative values in two's complement supports one more value than for the positive case.
            if ((value + 1).abs() >> (bitLength - 1) != 0) {
                revert CodecOverflow();
            }
        }
    }
}
