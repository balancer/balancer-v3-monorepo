// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { Slots } from "../openzeppelin/Slots.sol";

type NestedAddressMappingSlot is bytes32;
type AddressMappingSlot is bytes32;
type AddressArraySlot is bytes32;

library TransientStorageHelpers {
    using Slots for *;

    error TransientIndexOutOfBounds();

    /// Mappings

    function tGet(NestedAddressMappingSlot slot, address k1, IERC20 k2) internal view returns (int256) {
        return
            NestedAddressMappingSlot.unwrap(slot).deriveMapping(k1).deriveMapping(address(k2)).asInt256Slot().tload();
    }

    function tSet(NestedAddressMappingSlot slot, address k1, IERC20 k2, int256 value) internal {
        NestedAddressMappingSlot.unwrap(slot).deriveMapping(k1).deriveMapping(address(k2)).asInt256Slot().tstore(value);
    }

    function tGet(AddressMappingSlot slot, address key) internal view returns (uint256) {
        return AddressMappingSlot.unwrap(slot).deriveMapping(key).asUint256Slot().tload();
    }

    function tSet(AddressMappingSlot slot, address key, uint256 value) internal {
        AddressMappingSlot.unwrap(slot).deriveMapping(key).asUint256Slot().tstore(value);
    }

    // Implement the common "+=" operation: map[key] += value.
    function tAdd(AddressMappingSlot slot, address key, uint256 value) internal {
        AddressMappingSlot.unwrap(slot).deriveMapping(key).asUint256Slot().tstore(tGet(slot, key) + value);
    }

    // Implement the common "-=" operation: map[key] -= value.
    function tSub(AddressMappingSlot slot, address key, uint256 value) internal {
        AddressMappingSlot.unwrap(slot).deriveMapping(key).asUint256Slot().tstore(tGet(slot, key) - value);
    }

    /// Arrays

    function tLength(AddressArraySlot slot) internal view returns (uint256) {
        return AddressArraySlot.unwrap(slot).asUint256Slot().tload();
    }

    function tAt(AddressArraySlot slot, uint256 index) internal view returns (address) {
        _ensureIndexWithinBounds(slot, index);
        return AddressArraySlot.unwrap(slot).deriveArray().offset(index).asAddressSlot().tload();
    }

    function tSet(AddressArraySlot slot, uint256 index, address value) internal {
        _ensureIndexWithinBounds(slot, index);
        AddressArraySlot.unwrap(slot).deriveArray().offset(index).asAddressSlot().tstore(value);
    }

    function _ensureIndexWithinBounds(AddressArraySlot slot, uint256 index) private view {
        uint256 length = AddressArraySlot.unwrap(slot).asUint256Slot().tload();
        if (index >= length) {
            revert TransientIndexOutOfBounds();
        }
    }

    function tUncheckedAt(AddressArraySlot slot, uint256 index) internal view returns (address) {
        return AddressArraySlot.unwrap(slot).deriveArray().offset(index).asAddressSlot().tload();
    }

    function tUncheckedSet(AddressArraySlot slot, uint256 index, address value) internal {
        AddressArraySlot.unwrap(slot).deriveArray().offset(index).asAddressSlot().tstore(value);
    }

    function tPush(AddressArraySlot slot, address value) internal {
        uint256 length = AddressArraySlot.unwrap(slot).asUint256Slot().tload();
        AddressArraySlot.unwrap(slot).deriveArray().offset(length).asAddressSlot().tstore(value);
        AddressArraySlot.unwrap(slot).asUint256Slot().tstore(length + 1);
    }

    function tPop(AddressArraySlot slot) internal returns (address value) {
        uint256 lastElementIndex = AddressArraySlot.unwrap(slot).asUint256Slot().tload() - 1;
        // Update length to last element
        AddressArraySlot.unwrap(slot).asUint256Slot().tstore(lastElementIndex);
        Slots.AddressSlot lastElementOffset = AddressArraySlot
            .unwrap(slot)
            .deriveArray()
            .offset(lastElementIndex)
            .asAddressSlot();
        // Return last element
        value = lastElementOffset.tload();
        // Clear value in temporary storage
        lastElementOffset.tstore(address(0));
    }
}
