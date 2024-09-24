// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { TransientEnumerableSet } from "../../contracts/openzeppelin/TransientEnumerableSet.sol";

contract TransientEnumerableSetTest is Test {
    using TransientEnumerableSet for TransientEnumerableSet.AddressSet;

    TransientEnumerableSet.AddressSet private testSet;
    address internal constant ADDRESS_ONE = address(1);
    address internal constant ADDRESS_TWO = address(2);
    address internal constant ADDRESS_THREE = address(3);
    address internal constant NON_EXISTENT_ADDRESS = address(10);

    function setUp() public virtual {
        testSet.add(ADDRESS_ONE);
    }

    function testContains() public view {
        assertFalse(testSet.contains(ADDRESS_ONE), "Address added in another transaction found in testSet");
        assertFalse(testSet.contains(NON_EXISTENT_ADDRESS), "Non existent address found in testSet");
    }

    function testAdd() public {
        assertFalse(testSet.contains(ADDRESS_ONE), "Address to add found in testSet");
        assertTrue(testSet.add(ADDRESS_ONE), "add() return value is not true");
        assertTrue(testSet.contains(ADDRESS_ONE), "Address not found in testSet");
        // Cannot add an address that is already added.
        assertFalse(testSet.add(ADDRESS_ONE), "add() return value is not false");
        assertTrue(testSet.contains(ADDRESS_ONE), "Address not found in testSet");
    }

    function testRemove() public {
        assertFalse(testSet.contains(ADDRESS_ONE), "Address to add found in testSet");
        testSet.add(ADDRESS_ONE);
        assertTrue(testSet.contains(ADDRESS_ONE), "Address not found in testSet");
        assertTrue(testSet.remove(ADDRESS_ONE), "remove() return value is not true");
        assertFalse(testSet.contains(ADDRESS_ONE), "Address found in testSet after remove");
        // Cannot remove an address that is already removed.
        assertFalse(testSet.remove(ADDRESS_ONE), "remove() return value is not false");
        assertFalse(testSet.contains(ADDRESS_ONE), "Address found in testSet after remove");
    }

    function testAddAfterRemove() public {
        assertFalse(testSet.contains(ADDRESS_ONE), "Address to add found in testSet");
        testSet.add(ADDRESS_ONE);
        assertTrue(testSet.contains(ADDRESS_ONE), "Address not found in testSet");
        testSet.remove(ADDRESS_ONE);
        assertFalse(testSet.contains(ADDRESS_ONE), "Address found in testSet after remove");
        testSet.add(ADDRESS_ONE);
        assertTrue(testSet.contains(ADDRESS_ONE), "Address not found in testSet");
    }

    function testIndexOf() public {
        assertFalse(testSet.contains(ADDRESS_ONE), "Address to add found in testSet");
        testSet.add(ADDRESS_ONE);
        assertEq(testSet.indexOf(ADDRESS_ONE), 0, "Wrong index of ADDRESS_ONE");
        testSet.add(ADDRESS_TWO);
        assertEq(testSet.indexOf(ADDRESS_ONE), 0, "Wrong index of ADDRESS_ONE");
        assertEq(testSet.indexOf(ADDRESS_TWO), 1, "Wrong index of ADDRESS_TWO");
        testSet.add(ADDRESS_THREE);
        assertEq(testSet.indexOf(ADDRESS_ONE), 0, "Wrong index of ADDRESS_ONE");
        assertEq(testSet.indexOf(ADDRESS_TWO), 1, "Wrong index of ADDRESS_TWO");
        assertEq(testSet.indexOf(ADDRESS_THREE), 2, "Wrong index of ADDRESS_THREE");
    }

    function testIndexOfRevertEmptyArray() public {
        // Since array is empty, it should revert.
        vm.expectRevert(TransientEnumerableSet.ElementNotFound.selector);
        testSet.indexOf(ADDRESS_ONE);
    }

    function testIndexOfRevertNotExistentElement() public {
        testSet.add(ADDRESS_ONE);
        testSet.add(ADDRESS_TWO);
        assertEq(testSet.indexOf(ADDRESS_ONE), 0, "Wrong index of ADDRESS_ONE");
        assertEq(testSet.indexOf(ADDRESS_TWO), 1, "Wrong index of ADDRESS_TWO");
        // Since address is not in the array, it should revert.
        vm.expectRevert(TransientEnumerableSet.ElementNotFound.selector);
        testSet.indexOf(NON_EXISTENT_ADDRESS);
    }

    function testIndexOfRevertRemovedElement() public {
        testSet.add(ADDRESS_ONE);
        testSet.add(ADDRESS_TWO);
        assertEq(testSet.indexOf(ADDRESS_ONE), 0, "Wrong index of ADDRESS_ONE");
        assertEq(testSet.indexOf(ADDRESS_TWO), 1, "Wrong index of ADDRESS_TWO");
        testSet.remove(ADDRESS_ONE);
        // Since address is not in the array, it should revert.
        vm.expectRevert(TransientEnumerableSet.ElementNotFound.selector);
        testSet.indexOf(ADDRESS_ONE);
    }

    function testIndexOfAfterRemove() public {
        testSet.add(ADDRESS_ONE);
        testSet.add(ADDRESS_TWO);
        testSet.add(ADDRESS_THREE);
        assertEq(testSet.indexOf(ADDRESS_ONE), 0, "Wrong index of ADDRESS_ONE");
        assertEq(testSet.indexOf(ADDRESS_TWO), 1, "Wrong index of ADDRESS_TWO");
        assertEq(testSet.indexOf(ADDRESS_THREE), 2, "Wrong index of ADDRESS_THREE");
        assertTrue(testSet.remove(ADDRESS_TWO), "ADDRESS_TWO was not removed");
        assertEq(testSet.indexOf(ADDRESS_ONE), 0, "Wrong index of ADDRESS_ONE");
        // ADDRESS_THREE should move to position 1, to take the place of ADDRESS_TWO.
        assertEq(testSet.indexOf(ADDRESS_THREE), 1, "Wrong index of ADDRESS_THREE");
        testSet.add(ADDRESS_TWO);
        assertEq(testSet.indexOf(ADDRESS_ONE), 0, "Wrong index of ADDRESS_ONE");
        assertEq(testSet.indexOf(ADDRESS_THREE), 1, "Wrong index of ADDRESS_THREE");
        // ADDRESS_TWO was added at the end of the set.
        assertEq(testSet.indexOf(ADDRESS_TWO), 2, "Wrong index of ADDRESS_TWO");
    }

    function testLength() public {
        assertEq(testSet.length(), 0, "Length is not 0");
        testSet.add(ADDRESS_ONE);
        assertEq(testSet.length(), 1, "Length is not 1");
        testSet.add(ADDRESS_TWO);
        assertEq(testSet.length(), 2, "Length is not 2");
        testSet.add(ADDRESS_THREE);
        assertEq(testSet.length(), 3, "Length is not 3");
        testSet.remove(ADDRESS_TWO);
        assertEq(testSet.length(), 2, "Length is not 2");
        testSet.remove(ADDRESS_TWO);
        assertEq(testSet.length(), 2, "Length is not 2");
        testSet.remove(ADDRESS_ONE);
        assertEq(testSet.length(), 1, "Length is not 1");
        testSet.remove(ADDRESS_THREE);
        assertEq(testSet.length(), 0, "Length is not 0");
    }

    function testAt() public {
        testSet.add(ADDRESS_ONE);
        testSet.add(ADDRESS_TWO);
        testSet.add(ADDRESS_THREE);
        assertEq(testSet.at(0), ADDRESS_ONE, "Wrong element at index 0");
        assertEq(testSet.at(1), ADDRESS_TWO, "Wrong element at index 1");
        assertEq(testSet.at(2), ADDRESS_THREE, "Wrong element at index 2");
        testSet.remove(ADDRESS_TWO);
        assertEq(testSet.at(0), ADDRESS_ONE, "Wrong element at index 0");
        assertEq(testSet.at(1), ADDRESS_THREE, "Wrong element at index 1");
    }

    function testAtRevertEmptyArray() public {
        // Since array does not have any element, index 0 is out of bounds.
        vm.expectRevert(TransientEnumerableSet.IndexOutOfBounds.selector);
        testSet.at(0);
    }

    function testAtRevertOutOfBounds() public {
        testSet.add(ADDRESS_ONE);
        testSet.add(ADDRESS_TWO);
        assertEq(testSet.at(0), ADDRESS_ONE, "Wrong element at index 0");
        assertEq(testSet.at(1), ADDRESS_TWO, "Wrong element at index 1");
        // Since array has only 2 elements and is 0-based, index 2 is out of bounds.
        vm.expectRevert(TransientEnumerableSet.IndexOutOfBounds.selector);
        testSet.at(2);
    }

    function testAtRevertAfterRemove() public {
        testSet.add(ADDRESS_ONE);
        testSet.add(ADDRESS_TWO);
        testSet.add(ADDRESS_THREE);
        assertEq(testSet.at(0), ADDRESS_ONE, "Wrong element at index 0");
        assertEq(testSet.at(1), ADDRESS_TWO, "Wrong element at index 1");
        assertEq(testSet.at(2), ADDRESS_THREE, "Wrong element at index 2");
        testSet.remove(ADDRESS_TWO);
        assertEq(testSet.at(0), ADDRESS_ONE, "Wrong element at index 0");
        assertEq(testSet.at(1), ADDRESS_THREE, "Wrong element at index 1");
        // Since array has only 2 elements and is 0-based, index 2 is out of bounds.
        vm.expectRevert(TransientEnumerableSet.IndexOutOfBounds.selector);
        testSet.at(2);
    }

    function testUncheckedAt() public {
        testSet.add(ADDRESS_ONE);
        testSet.add(ADDRESS_TWO);
        testSet.add(ADDRESS_THREE);
        assertEq(testSet.unchecked_at(0), ADDRESS_ONE, "Wrong element at index 0");
        assertEq(testSet.unchecked_at(1), ADDRESS_TWO, "Wrong element at index 1");
        assertEq(testSet.unchecked_at(2), ADDRESS_THREE, "Wrong element at index 2");
        testSet.remove(ADDRESS_TWO);
        assertEq(testSet.unchecked_at(0), ADDRESS_ONE, "Wrong element at index 0");
        assertEq(testSet.unchecked_at(1), ADDRESS_THREE, "Wrong element at index 1");
    }

    function testUncheckedAtOutOfBounds() public view {
        assertEq(testSet.unchecked_at(0), address(0), "unchecked_at() did not return a 0x0 address");
    }

    function testValues() public {
        address[] memory values = testSet.values();
        assertEq(values.length, 0, "Wrong values length");
        testSet.add(ADDRESS_ONE);
        testSet.add(ADDRESS_TWO);
        testSet.add(ADDRESS_THREE);
        values = testSet.values();
        assertEq(values.length, 3, "Wrong values length");
        assertEq(values[0], ADDRESS_ONE, "Wrong element at position 0 of values");
        assertEq(values[1], ADDRESS_TWO, "Wrong element at position 1 of values");
        assertEq(values[2], ADDRESS_THREE, "Wrong element at position 2 of values");
        testSet.remove(ADDRESS_TWO);
        values = testSet.values();
        assertEq(values.length, 2, "Wrong values length");
        assertEq(values[0], ADDRESS_ONE, "Wrong element at position 0 of values");
        assertEq(values[1], ADDRESS_THREE, "Wrong element at position 1 of values");
        testSet.remove(ADDRESS_ONE);
        testSet.remove(ADDRESS_THREE);
        values = testSet.values();
        assertEq(values.length, 0, "Wrong values length");
    }

    function testUncheckedIndexOf() public {
        testSet.add(ADDRESS_ONE);
        assertEq(testSet.unchecked_indexOf(ADDRESS_ONE), 0, "Wrong index of ADDRESS_ONE");
        testSet.add(ADDRESS_TWO);
        assertEq(testSet.unchecked_indexOf(ADDRESS_ONE), 0, "Wrong index of ADDRESS_ONE");
        assertEq(testSet.unchecked_indexOf(ADDRESS_TWO), 1, "Wrong index of ADDRESS_TWO");
        testSet.add(ADDRESS_THREE);
        assertEq(testSet.unchecked_indexOf(ADDRESS_ONE), 0, "Wrong index of ADDRESS_ONE");
        assertEq(testSet.unchecked_indexOf(ADDRESS_TWO), 1, "Wrong index of ADDRESS_TWO");
        assertEq(testSet.unchecked_indexOf(ADDRESS_THREE), 2, "Wrong index of ADDRESS_THREE");
    }

    function testUncheckedIndexOfNonExistentElement() public {
        testSet.add(ADDRESS_ONE);
        testSet.add(ADDRESS_TWO);
        testSet.add(ADDRESS_THREE);
        // unchecked_indexOf does not revert if element does not exist. Instead, it returns 0.
        assertEq(testSet.unchecked_indexOf(NON_EXISTENT_ADDRESS), 0, "Wrong index of NON_EXISTENT_ADDRESS");
    }
}
