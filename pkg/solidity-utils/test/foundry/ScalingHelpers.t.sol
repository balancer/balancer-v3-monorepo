// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { InputHelpers } from "../../contracts/helpers/InputHelpers.sol";
import { ScalingHelpers } from "../../contracts/helpers/ScalingHelpers.sol";

contract ScalingHelpersTest is Test {
    function testCopyToArray__Fuzz(uint256[4] memory input) public pure {
        uint256[] memory from = new uint256[](4);
        from[0] = input[0];
        from[1] = input[1];
        from[2] = input[2];
        from[3] = input[3];

        uint256[] memory to = new uint256[](4);

        uint256 freeMemoryPointerBefore;
        assembly ("memory-safe") {
            freeMemoryPointerBefore := mload(0x40)
        }

        // Array length is 4; past array is 5.
        uint256 memoryPastArrayBefore;
        assembly ("memory-safe") {
            memoryPastArrayBefore := mload(add(to, mul(5, 0x20)))
        }

        uint256 memoryPreArrayBefore;
        assembly ("memory-safe") {
            memoryPreArrayBefore := mload(sub(to, 0x20))
        }

        uint256 fromLengthBefore = from.length;
        uint256 toLengthBefore = to.length;

        ScalingHelpers.copyToArray(from, to);

        uint256 freeMemoryPointerAfter;
        assembly ("memory-safe") {
            freeMemoryPointerAfter := mload(0x40)
        }

        uint256 memoryPastArrayAfter;
        assembly ("memory-safe") {
            memoryPastArrayAfter := mload(add(to, mul(5, 0x20)))
        }

        uint256 memoryPreArrayAfter;
        assembly ("memory-safe") {
            memoryPreArrayAfter := mload(sub(to, 0x20))
        }

        // From is not modified.
        assertEq(from[0], input[0], "from [0]");
        assertEq(from[1], input[1], "from [1]");
        assertEq(from[2], input[2], "from [2]");
        assertEq(from[3], input[3], "from [3]");

        // From == to.
        assertEq(from[0], to[0], "to [0]");
        assertEq(from[1], to[1], "to [1]");
        assertEq(from[2], to[2], "to [2]");
        assertEq(from[3], to[3], "to [3]");

        // Memory array and memory past to are ok
        assertEq(freeMemoryPointerBefore, freeMemoryPointerAfter, "Free memory pointer was modified");
        assertEq(memoryPastArrayBefore, memoryPastArrayAfter, "Memory past array was modified");
        assertEq(memoryPreArrayBefore, memoryPreArrayAfter, "Memory before array was modified");
        assertEq(fromLengthBefore, from.length, "From length was modified");
        assertEq(toLengthBefore, to.length, "To length was modified");
    }

    function testCopyToArray__Fuzz(uint256[8] memory input, uint256 length) public pure {
        length = bound(length, 2, 8);
        uint256[] memory from = new uint256[](length);
        for (uint256 i = 0; i < length; ++i) {
            from[i] = input[i];
        }

        uint256[] memory to = new uint256[](length);

        uint256 freeMemoryPointerBefore;
        assembly ("memory-safe") {
            freeMemoryPointerBefore := mload(0x40)
        }

        // Array length is 4; past array is 5.
        uint256 memoryPastArrayBefore;
        assembly ("memory-safe") {
            memoryPastArrayBefore := mload(add(to, mul(add(length, 1), 0x20)))
        }

        uint256 memoryPreArrayBefore;
        assembly ("memory-safe") {
            memoryPreArrayBefore := mload(sub(to, 0x20))
        }

        uint256 fromLengthBefore = from.length;
        uint256 toLengthBefore = to.length;

        ScalingHelpers.copyToArray(from, to);

        uint256 freeMemoryPointerAfter;
        assembly ("memory-safe") {
            freeMemoryPointerAfter := mload(0x40)
        }

        uint256 memoryPastArrayAfter;
        assembly ("memory-safe") {
            memoryPastArrayAfter := mload(add(to, mul(add(length, 1), 0x20)))
        }

        uint256 memoryPreArrayAfter;
        assembly ("memory-safe") {
            memoryPreArrayAfter := mload(sub(to, 0x20))
        }

        for (uint256 i = 0; i < length; ++i) {
            assertEq(from[i], input[i], "from");
            assertEq(from[i], to[i], "to");
        }

        // Memory array and memory past to are ok
        assertEq(freeMemoryPointerBefore, freeMemoryPointerAfter, "Free memory pointer was modified");
        assertEq(memoryPastArrayBefore, memoryPastArrayAfter, "Memory past array was modified");
        assertEq(memoryPreArrayBefore, memoryPreArrayAfter, "Memory before array was modified");
        assertEq(fromLengthBefore, from.length, "From length was modified");
        assertEq(toLengthBefore, to.length, "To length was modified");
    }

    function testCopyToArrayLengthMismatch() public {
        uint256[] memory from = new uint256[](4);
        uint256[] memory to = new uint256[](3);
        vm.expectRevert(InputHelpers.InputLengthMismatch.selector);
        ScalingHelpers.copyToArray(from, to);
    }
}
