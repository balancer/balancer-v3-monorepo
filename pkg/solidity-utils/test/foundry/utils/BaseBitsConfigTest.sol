// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

contract BaseBitsConfigTest is Test {
    struct Bits {
        uint256 startBit;
        uint256 size;
    }

    mapping(uint256 => bool) usedBits;

    // This function checks that the bits are used once and follow each other
    function _checkBitsUsedOnce(Bits[] memory bits) internal {
        uint256 nextStartBit = 0;
        for (uint256 i = 0; i < bits.length; i++) {
            uint256 startBit = bits[i].startBit;

            assertEq(startBit, nextStartBit, "Bits do not follow each other");

            uint256 endBit = startBit + bits[i].size;
            for (uint256 j = startBit; j < endBit; j++) {
                _checkBitUsedOnce(j);
            }

            nextStartBit = endBit;
        }
    }

    function _checkBitUsedOnce(uint256 bitNumber) private {
        assertEq(usedBits[bitNumber], false, "Bit already used");
        usedBits[bitNumber] = true;
    }
}
