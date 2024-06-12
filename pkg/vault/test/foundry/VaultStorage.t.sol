// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { StorageSlot } from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/StorageSlot.sol";
import {
    TokenDeltaMappingSlotType
} from "@balancer-labs/v3-solidity-utils/contracts/helpers/TransientStorageHelpers.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract VaultStorageTest is BaseVaultTest {
    function setUp() public virtual override {
        BaseVaultTest.setUp();
    }

    function testGetIsUnlockedSlot() external {
        assertEq(
            StorageSlot.BooleanSlotType.unwrap(vault.manualGetIsUnlockedSlot()),
            keccak256(abi.encode(uint256(keccak256("balancer-labs.v3.storage.VaultStorage.isUnlocked")) - 1)) &
                ~bytes32(uint256(0xff))
        );
    }

    function testGetNonzeroDeltaCountSlot() external {
        assertEq(
            StorageSlot.Uint256SlotType.unwrap(vault.manualGetNonzeroDeltaCountSlot()),
            keccak256(abi.encode(uint256(keccak256("balancer-labs.v3.storage.VaultStorage.nonZeroDeltaCount")) - 1)) &
                ~bytes32(uint256(0xff))
        );
    }

    function testGetTokenDeltasSlot() external {
        assertEq(
            TokenDeltaMappingSlotType.unwrap(vault.manualGetTokenDeltasSlot()),
            keccak256(abi.encode(uint256(keccak256("balancer-labs.v3.storage.VaultStorage.tokenDelta")) - 1)) &
                ~bytes32(uint256(0xff))
        );
    }
}
