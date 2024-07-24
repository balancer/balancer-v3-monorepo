// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {
    AddressArraySlotType,
    AddressMappingSlot,
    TransientStorageHelpers
} from "../helpers/TransientStorageHelpers.sol";
import "./StorageSlotExtension.sol";

/**
 * @notice Library for managing sets of primitive types.
 * @dev See https://en.wikipedia.org/wiki/Set_(abstract_data_type)[sets] of primitive types.
 *
 * Based on the EnumerableSet library from OpenZeppelin Contracts, altered to remove the base private functions that
 * work on bytes32, replacing them with a native implementation for address values, to reduce bytecode size and
 * runtime costs. It also uses transient storage.
 *
 * The `unchecked_at` function was also added, which allows for more gas efficient data reads in some scenarios.
 *
 * Sets have the following properties:
 *
 * - Elements are added, removed, and checked for existence in constant time (O(1)).
 * - Elements are enumerated in O(n). No guarantees are made on the ordering.
 *
 * ```
 * contract Example {
 *     // Add the library methods
 *     using TransientEnumerableSet for TransientEnumerableSet.AddressSet;
 *
 *     // Declare a set state variable
 *     TransientEnumerableSet.AddressSet private mySet;
 * }
 * ```
 */
library TransientEnumerableSet {
    using TransientStorageHelpers for *;
    using StorageSlotExtension for StorageSlotExtension.Uint256SlotType;

    // The original OpenZeppelin implementation uses a generic Set type with bytes32 values: this was replaced with
    // AddressSet, which uses address keys natively, resulting in more dense bytecode.

    // solhint-disable func-name-mixedcase

    struct AddressSet {
        // Storage of set values
        address[] __values;
        // Position of the value in the `values` array, plus 1 because index 0
        // means a value is not in the set.
        mapping(address => uint256) __indexes;
    }

    /// @dev An index is beyond the current bounds of the set.
    error IndexOutOfBounds();

    /// @dev An element that is not present in the set.
    error ElementNotFound();

    /**
     * @dev Add a value to a set. O(1).
     *
     * Returns true if the value was added to the set, if it was not already present.
     */
    function add(AddressSet storage set, address value) internal returns (bool) {
        if (!contains(set, value)) {
            _values(set).tPush(value);

            // The value is stored at length-1, but we add 1 to all indexes
            // and use 0 as a sentinel value
            _indexes(set).tSet(value, _values(set).tLength());

            return true;
        } else {
            return false;
        }
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the value was removed from the set, that is if it was
     * present.
     */
    function remove(AddressSet storage set, address value) internal returns (bool) {
        // We read and store the value's index to prevent multiple reads from the same storage slot
        uint256 valueIndex = _indexes(set).tGet(value);

        if (valueIndex != 0) {
            // Equivalent to contains(set, value)
            // To delete an element from the _values array in O(1), we swap the element to delete with the last one in
            // the array, and then remove the last element (sometimes called as 'swap and pop').
            // This modifies the order of the array, as noted in {at}.
            uint256 toDeleteIndex;
            uint256 lastIndex;

            unchecked {
                toDeleteIndex = valueIndex - 1;
                lastIndex = _values(set).tLength() - 1;
            }

            // The swap is only necessary if we're not removing the last element
            if (toDeleteIndex != lastIndex) {
                address lastValue = _values(set).tAt(lastIndex);

                // Move the last value to the index where the value to delete is
                _values(set).tSet(toDeleteIndex, lastValue);

                // Update the index for the moved value
                _indexes(set).tSet(lastValue, valueIndex); // = toDeleteIndex + 1; all indices are 1-based
            }

            // Delete the slot where the moved value was stored
            _values(set).tPop();

            // We need to delete the index for the deleted slot with transient storage because another operation in the
            // same transaction may want to add the same element to the array again.
            _indexes(set).tSet(value, 0);

            return true;
        } else {
            return false;
        }
    }

    /// @dev Returns true if the value is in the set. O(1).
    function contains(AddressSet storage set, address value) internal view returns (bool) {
        return _indexes(set).tGet(value) != 0;
    }

    /// @dev Returns the number of values on the set. O(1).
    function length(AddressSet storage set) internal view returns (uint256) {
        return _values(set).tLength();
    }

    /**
     * @dev Returns the value stored at position `index` in the set. O(1).
     *
     * Note that there are no guarantees on the ordering of values inside the
     * array, and it may change when more values are added or removed.
     *
     * Requirements:
     *
     * - `index` must be strictly less than {length}.
     */
    function at(AddressSet storage set, uint256 index) internal view returns (address) {
        if (index >= _values(set).tLength()) {
            revert IndexOutOfBounds();
        }

        return unchecked_at(set, index);
    }

    /**
     * @dev Same as {at}, except this doesn't revert if `index` it outside of the set (i.e. if it is equal or larger
     * than {length}). O(1).
     *
     * This function performs one less storage read than {at}, but should only be used when `index` is known to be
     * within bounds.
     */
    function unchecked_at(AddressSet storage set, uint256 index) internal view returns (address) {
        return _values(set).tUncheckedAt(index);
    }

    /// @dev Return the index of an element in the set, or revert if not found.
    function indexOf(AddressSet storage set, address value) internal view returns (uint256) {
        uint256 rawIndex = _indexes(set).tGet(value);

        if (rawIndex == 0) {
            revert ElementNotFound();
        }

        unchecked {
            return rawIndex - 1;
        }
    }

    /**
     * @dev Same as {indexOf}, except this doesn't revert if the element isn't present in the set.
     * In this case, it returns 0.
     *
     * This function performs one less storage read than {indexOf}, but should only be used when `index` is known to be
     * within bounds.
     */
    function unchecked_indexOf(AddressSet storage set, address value) internal view returns (uint256) {
        uint256 rawIndex = _indexes(set).tGet(value);

        unchecked {
            return rawIndex == 0 ? 0 : rawIndex - 1;
        }
    }

    // Transient storage functions

    /// @dev Return the raw contents of the underlying address array.
    function values(AddressSet storage set) internal view returns (address[] memory memValues) {
        uint256 len = _values(set).tLength();
        memValues = new address[](len);

        for (uint256 i = 0; i < len; ++i) {
            memValues[i] = _values(set).tUncheckedAt(i);
        }
    }

    function _values(AddressSet storage set) private view returns (AddressArraySlotType slot) {
        address[] storage structValues = set.__values;

        // solhint-disable-next-line no-inline-assembly
        assembly {
            slot := structValues.slot
        }
    }

    function _indexes(AddressSet storage set) private view returns (AddressMappingSlot slot) {
        mapping(address => uint256) storage indexes = set.__indexes;

        // solhint-disable-next-line no-inline-assembly
        assembly {
            slot := indexes.slot
        }
    }
}
