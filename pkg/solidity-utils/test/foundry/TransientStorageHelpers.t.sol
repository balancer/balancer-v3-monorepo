// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../../contracts/helpers/TransientStorageHelpers.sol";
import "../../contracts/openzeppelin/StorageSlotExtension.sol";

contract TransientStorageHelpersTest is Test {
    using TransientStorageHelpers for *;
    using StorageSlotExtension for StorageSlotExtension.Uint256SlotType;

    mapping(IERC20 => int256) private tokenDeltaMapping;
    address[] private addressArray;
    uint256 private storageUint;

    function testTransientNestedMapping__Fuzz(address k1, int256 value) public {
        tokenDeltaMapping[IERC20(k1)] = 1234;

        TokenDeltaMappingSlotType transientMapping;
        assembly {
            transientMapping := tokenDeltaMapping.slot
        }

        assertEq(transientMapping.tGet(IERC20(k1)), 0, "Mapping: Initial nonzero value");

        transientMapping.tSet(IERC20(k1), value);
        assertEq(transientMapping.tGet(IERC20(k1)), value, "Mapping: Incorrect value set");
        assertEq(tokenDeltaMapping[IERC20(k1)], 1234, "Mapping: storage was modified");
    }

    function testTransientAddressArray() public {
        addressArray.push(address(1));
        addressArray.push(address(2));
        addressArray.push(address(3));
        require(addressArray.length == 3, "Array: wrong initial conditions");

        AddressArraySlotType transientArray;
        assembly {
            transientArray := addressArray.slot
        }

        assertEq(transientArray.tLength(), 0, "Array: Initial nonzero value");

        transientArray.tPush(address(9));
        transientArray.tPush(address(8));
        transientArray.tPush(address(7));
        transientArray.tPush(address(6));

        assertEq(transientArray.tLength(), 4, "Array: incorrect length after push");
        assertEq(addressArray.length, 3, "Array: storage modified");

        assertEq(transientArray.tAt(0), address(9), "Array[0]: incorrect value");
        assertEq(transientArray.tAt(1), address(8), "Array[1]: incorrect value");
        assertEq(transientArray.tAt(2), address(7), "Array[2]: incorrect value");
        assertEq(transientArray.tAt(3), address(6), "Array[3]: incorrect value");

        assertEq(transientArray.tUncheckedAt(0), address(9), "Array[0] (unchecked): incorrect value");
        assertEq(transientArray.tUncheckedAt(1), address(8), "Array[1] (unchecked): incorrect value");
        assertEq(transientArray.tUncheckedAt(2), address(7), "Array[2] (unchecked): incorrect value");
        assertEq(transientArray.tUncheckedAt(3), address(6), "Array[3] (unchecked): incorrect value");

        transientArray.tSet(1, address(1111));
        assertEq(transientArray.tAt(1), address(1111), "Array[1]: incorrect value after edit");
        assertEq(transientArray.tUncheckedAt(1), address(1111), "Array[1]: incorrect value after edit");

        transientArray.tUncheckedSet(2, address(2222));
        assertEq(transientArray.tAt(2), address(2222), "Array[2]: incorrect value after edit");
        assertEq(transientArray.tUncheckedAt(2), address(2222), "Array[2]: incorrect value after edit");

        assertEq(transientArray.tPop(), address(6), "Pop[3]: incorrect value");
        assertEq(transientArray.tLength(), 3, "Pop[3]: incorrect length");
        assertEq(transientArray.tPop(), address(2222), "Pop[2]: incorrect value");
        assertEq(transientArray.tLength(), 2, "Pop[2]: incorrect length");
        assertEq(transientArray.tPop(), address(1111), "Pop[1]: incorrect value");
        assertEq(transientArray.tLength(), 1, "Pop[1]: incorrect length");
        assertEq(transientArray.tPop(), address(9), "Pop[0]: incorrect value");
        assertEq(transientArray.tLength(), 0, "Pop[0]: incorrect length");

        assertEq(addressArray.length, 3, "Array: storage modified");
    }

    function testTransientArrayFailures() public {
        AddressArraySlotType transientArray;
        assembly {
            transientArray := addressArray.slot
        }

        vm.expectRevert(stdError.arithmeticError);
        transientArray.tPop();

        transientArray.tPush(address(1));
        transientArray.tPush(address(2));
        transientArray.tPush(address(3));

        assertEq(transientArray.tLength(), 3, "Array: incorrect length after push");

        vm.expectRevert(TransientStorageHelpers.TransientIndexOutOfBounds.selector);
        transientArray.tAt(4);

        vm.expectRevert(TransientStorageHelpers.TransientIndexOutOfBounds.selector);
        transientArray.tSet(4, address(1));
    }

    function testTransientUint__Fuzz(uint256 value) public {
        storageUint = 1234;

        StorageSlotExtension.Uint256SlotType transientUint;
        assembly {
            transientUint := storageUint.slot
        }

        assertEq(transientUint.tload(), 0, "Uint: initial nonzero value");
        transientUint.tstore(value);
        assertEq(transientUint.tload(), value, "Uint: incorrect value after edit");
        assertEq(storageUint, 1234, "Uint: storage modified");
    }

    function testTransientUintIncrement__Fuzz(uint256 value) public {
        vm.assume(value != type(uint256).max);
        storageUint = 1234;

        StorageSlotExtension.Uint256SlotType transientUint;
        assembly {
            transientUint := storageUint.slot
        }

        assertEq(transientUint.tload(), 0, "Uint: initial nonzero value");
        transientUint.tstore(value);
        transientUint.tIncrement();
        assertEq(transientUint.tload(), value + 1, "Uint: incorrect value after increment");

        assertEq(storageUint, 1234, "Uint: storage modified");
    }

    function testTransientUintDecrement__Fuzz(uint256 value) public {
        vm.assume(value != 0);
        storageUint = 1234;

        StorageSlotExtension.Uint256SlotType transientUint;
        assembly {
            transientUint := storageUint.slot
        }

        assertEq(transientUint.tload(), 0, "Uint: initial nonzero value");
        transientUint.tstore(value);
        transientUint.tDecrement();
        assertEq(transientUint.tload(), value - 1, "Uint: incorrect value after increment");

        assertEq(storageUint, 1234, "Uint: storage modified");
    }

    function testTransientIncrementOverflow() public {
        StorageSlotExtension.Uint256SlotType transientUint;
        assembly {
            transientUint := storageUint.slot
        }

        transientUint.tstore(type(uint256).max);

        vm.expectRevert(stdError.arithmeticError);
        transientUint.tIncrement();
    }

    function testTransientDecrementUnderflow() public {
        StorageSlotExtension.Uint256SlotType transientUint;
        assembly {
            transientUint := storageUint.slot
        }

        transientUint.tstore(0);

        vm.expectRevert(stdError.arithmeticError);
        transientUint.tDecrement();
    }

    function testCalculateSlot() public pure {
        bytes32 slot = TransientStorageHelpers.calculateSlot("domain", "name");
        assertEq(
            slot,
            keccak256(abi.encode(uint256(keccak256(abi.encodePacked("balancer-labs.v3.storage.domain.name"))) - 1)) &
                ~bytes32(uint256(0xff))
        );
    }
}
