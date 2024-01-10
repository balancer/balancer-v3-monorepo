// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { IVaultMain } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultMain.sol";

import { Vault } from "../../contracts/Vault.sol";
import { VaultExtensionMock } from "../../contracts/test/VaultExtensionMock.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract VaultDefaultHandlers is BaseVaultTest {
    function setUp() public virtual override {
        BaseVaultTest.setUp();
    }

    function testReceive() public {
        vm.prank(alice);
        vm.expectRevert(IVaultMain.CannotReceiveEth);
        address(vault).send(1);
    }
}
