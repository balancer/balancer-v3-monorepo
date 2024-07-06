// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import { StorageSlotExtension } from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/StorageSlotExtension.sol";

import {
    TransientStorageHelpers,
    TokenDeltaMappingSlotType
} from "@balancer-labs/v3-solidity-utils/contracts/helpers/TransientStorageHelpers.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract VaultStorageTest is BaseVaultTest {
    function setUp() public virtual override {
        BaseVaultTest.setUp();
    }

    function testGetIsUnlockedSlot() external view {
        assertEq(
            StorageSlotExtension.BooleanSlotType.unwrap(vault.manualGetIsUnlocked()),
            TransientStorageHelpers.calculateSlot("VaultStorage", "isUnlocked")
        );
    }

    function testGetNonzeroDeltaCountSlot() external view {
        assertEq(
            StorageSlotExtension.Uint256SlotType.unwrap(vault.manualGetNonzeroDeltaCount()),
            TransientStorageHelpers.calculateSlot("VaultStorage", "nonZeroDeltaCount")
        );
    }

    function testGetTokenDeltasSlot() external view {
        assertEq(
            TokenDeltaMappingSlotType.unwrap(vault.manualGetTokenDeltas()),
            TransientStorageHelpers.calculateSlot("VaultStorage", "tokenDeltas")
        );
    }
}
