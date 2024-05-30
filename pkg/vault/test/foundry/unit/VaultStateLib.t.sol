// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { VaultState } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { VaultStateBits, VaultStateLib } from "../../../contracts/lib/VaultStateLib.sol";

contract VaultStateLibTest is Test {
    // 3 flags = 3 total bits used.
    uint256 private constant CONFIG_MSB = 3;

    function testToAndFromVaultStateBits__Fuzz(uint256 rawConfigInt) public {
        rawConfigInt = bound(rawConfigInt, 0, uint256(1 << CONFIG_MSB) - 1);
        bytes32 rawConfig = bytes32(rawConfigInt);
        VaultState memory config = VaultStateLib.toVaultState(VaultStateBits.wrap(rawConfig));
        bytes32 configBytes32 = VaultStateBits.unwrap(VaultStateLib.fromVaultState(config));

        assertEq(rawConfig, configBytes32);
    }

    function testUnusedVaultStateBits() public {
        bytes32 unusedBits = bytes32(uint256(type(uint256).max << (CONFIG_MSB + 1)));

        VaultState memory config = VaultStateLib.toVaultState(VaultStateBits.wrap(unusedBits));
        bytes32 configBytes32 = VaultStateBits.unwrap(VaultStateLib.fromVaultState(config));

        assertEq(bytes32(0), configBytes32);
    }
}
