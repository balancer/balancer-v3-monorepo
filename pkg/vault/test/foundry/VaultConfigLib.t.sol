// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { VaultConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { VaultConfigBits, VaultConfigLib } from "../../contracts/lib/VaultConfigLib.sol";

contract VaultConfigLibTest is Test {
    uint256 private constant CONFIG_MSB = 2162720;

    function testToAndFromVaultConfigBits__Fuzz(uint256 rawConfigInt) public {
        rawConfigInt = bound(rawConfigInt, 0, uint256(1 << CONFIG_MSB));
        bytes32 rawConfig = bytes32(rawConfigInt);
        VaultConfig memory config = VaultConfigLib.toVaultConfig(VaultConfigBits.wrap(rawConfig));
        bytes32 configBytes32 = VaultConfigBits.unwrap(VaultConfigLib.fromVaultConfig(config));

        assertEq(rawConfig, configBytes32);
    }

    function testUnusedVaultConfigBits() public {
        bytes32 unusedBits = bytes32(uint256(type(uint256).max << (CONFIG_MSB + 1)));

        VaultConfig memory config = VaultConfigLib.toVaultConfig(VaultConfigBits.wrap(unusedBits));
        bytes32 configBytes32 = VaultConfigBits.unwrap(VaultConfigLib.fromVaultConfig(config));

        assertEq(bytes32(0), configBytes32);
    }
}
