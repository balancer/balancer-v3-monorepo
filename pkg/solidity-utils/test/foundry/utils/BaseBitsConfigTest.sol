// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

contract BaseBitsConfigTest is Test {
    mapping(uint256 => bool) usedBits;

    function _checkBitsUsedOnce(uint256 startBit, uint256 size) internal {
        uint256 endBit = startBit + size;
        for (uint256 i = startBit; i < endBit; i++) {
            _checkBitsUsedOnce(i);
        }
    }

    function _checkBitsUsedOnce(uint256 bitNumber) internal {
        assertEq(usedBits[bitNumber], false, "Bit already used");
        usedBits[bitNumber] = true;
    }
}
