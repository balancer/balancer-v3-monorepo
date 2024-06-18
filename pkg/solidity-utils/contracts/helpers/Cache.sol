// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { StorageSlot } from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/StorageSlot.sol";

library Cache {
    struct AddressCache {
        address value;
        bytes32 slot;
    }

    function initAddressCache(
        StorageSlot.AddressSlot storage addressSlot
    ) internal pure returns (AddressCache memory cache) {
        bytes32 slot;

        assembly {
            slot := addressSlot.slot
        }

        cache.slot = slot;
    }

    function getValue(AddressCache memory cache) internal view returns (address) {
        if (cache.value == address(0)) {
            address _value;
            bytes32 slot = cache.slot;

            assembly {
                _value := sload(slot)
            }

            cache.value = _value;
        }

        return cache.value;
    }
}
