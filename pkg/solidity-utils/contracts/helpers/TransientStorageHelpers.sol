// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { SlotDerivation } from "../openzeppelin/SlotDerivation.sol";
import { StorageSlot } from "../openzeppelin/StorageSlot.sol";

type NestedAddressMappingSlotType is bytes32;
type AddressMappingSlot is bytes32;
type AddressArraySlotType is bytes32;

library TransientStorageHelpers {
    using SlotDerivation for *;
    using StorageSlot for *;

    error TransientIndexOutOfBounds();

    // Mappings

    function tGet(NestedAddressMappingSlotType slot, address k1, IERC20 k2) internal view returns (int256) {
        return
            NestedAddressMappingSlotType.unwrap(slot).deriveMapping(k1).deriveMapping(address(k2)).asInt256().tload();
    }

    function tSet(NestedAddressMappingSlotType slot, address k1, IERC20 k2, int256 value) internal {
        NestedAddressMappingSlotType.unwrap(slot).deriveMapping(k1).deriveMapping(address(k2)).asInt256().tstore(value);
    }

    function tGet(AddressMappingSlot slot, address key) internal view returns (uint256) {
        return AddressMappingSlot.unwrap(slot).deriveMapping(key).asUint256().tload();
    }

    function tSet(AddressMappingSlot slot, address key, uint256 value) internal {
        AddressMappingSlot.unwrap(slot).deriveMapping(key).asUint256().tstore(value);
    }

    // Implement the common "+=" operation: map[key] += value.
    function tAdd(AddressMappingSlot slot, address key, uint256 value) internal {
        AddressMappingSlot.unwrap(slot).deriveMapping(key).asUint256().tstore(tGet(slot, key) + value);
    }

    function tSub(AddressMappingSlot slot, address key, uint256 value) internal {
        AddressMappingSlot.unwrap(slot).deriveMapping(key).asUint256().tstore(tGet(slot, key) - value);
    }
    
    // Arrays

    function tLength(AddressArraySlotType slot) internal view returns (uint256) {
        return AddressArraySlotType.unwrap(slot).asUint256().tload();
    }

    function tAt(AddressArraySlotType slot, uint256 index) internal view returns (address) {
        _ensureIndexWithinBounds(slot, index);
        return AddressArraySlotType.unwrap(slot).deriveArray().offset(index).asAddress().tload();
    }

    function tSet(AddressArraySlotType slot, uint256 index, address value) internal {
        _ensureIndexWithinBounds(slot, index);
        AddressArraySlotType.unwrap(slot).deriveArray().offset(index).asAddress().tstore(value);
    }

    function _ensureIndexWithinBounds(AddressArraySlotType slot, uint256 index) private view {
        uint256 length = AddressArraySlotType.unwrap(slot).asUint256().tload();
        if (index >= length) {
            revert TransientIndexOutOfBounds();
        }
    }

    function tUncheckedAt(AddressArraySlotType slot, uint256 index) internal view returns (address) {
        return AddressArraySlotType.unwrap(slot).deriveArray().offset(index).asAddress().tload();
    }

    function tUncheckedSet(AddressArraySlotType slot, uint256 index, address value) internal {
        AddressArraySlotType.unwrap(slot).deriveArray().offset(index).asAddress().tstore(value);
    }

    function tPush(AddressArraySlotType slot, address value) internal {
        // Store the value at offset corresponding to the current length.
        uint256 length = AddressArraySlotType.unwrap(slot).asUint256().tload();
        AddressArraySlotType.unwrap(slot).deriveArray().offset(length).asAddress().tstore(value);
        // Update current length to consider the new value.
        AddressArraySlotType.unwrap(slot).asUint256().tstore(length + 1);
    }

    function tPop(AddressArraySlotType slot) internal returns (address value) {
        uint256 lastElementIndex = AddressArraySlotType.unwrap(slot).asUint256().tload() - 1;
        // Update length to last element. When the index is 0, the slot that holds the length is cleared out.
        AddressArraySlotType.unwrap(slot).asUint256().tstore(lastElementIndex);
        StorageSlot.AddressSlotType lastElementSlot = AddressArraySlotType
            .unwrap(slot)
            .deriveArray()
            .offset(lastElementIndex)
            .asAddress();
        // Return last element.
        value = lastElementSlot.tload();
        // Clear value in temporary storage.
        lastElementSlot.tstore(address(0));
    }

    // Uint256

    function tIncrement(StorageSlot.Uint256SlotType slot) internal {
        slot.tstore(slot.tload() + 1);
    }

    function tDecrement(StorageSlot.Uint256SlotType slot) internal {
        slot.tstore(slot.tload() - 1);
    }
}
