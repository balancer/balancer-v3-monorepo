// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { StorageSlot } from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/StorageSlot.sol";
import {
    TokenDeltaMappingSlotType
} from "@balancer-labs/v3-solidity-utils/contracts/helpers/TransientStorageHelpers.sol";

interface IVaultStorageMock {
    function manualGetIsUnlocked() external pure returns (StorageSlot.BooleanSlotType slot);

    function manualGetNonzeroDeltaCount() external pure returns (StorageSlot.Uint256SlotType slot);

    function manualGetTokenDeltas() external pure returns (TokenDeltaMappingSlotType slot);
}
