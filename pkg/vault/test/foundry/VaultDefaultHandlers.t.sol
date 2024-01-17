// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { CannotReceiveEth, NotVaultDelegateCall } from "@balancer-labs/v3-interfaces/contracts/vault/VaultErrors.sol";

import { Vault } from "../../contracts/Vault.sol";
import { VaultExtensionMock } from "../../contracts/test/VaultExtensionMock.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract VaultDefaultHandlers is BaseVaultTest {
    function setUp() public virtual override {
        BaseVaultTest.setUp();
    }

    function testReceive() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(CannotReceiveEth.selector));
        payable(vault).transfer(1);
    }

    function testDefaultHandlerWithEth() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(CannotReceiveEth.selector));
        VaultExtensionMock(payable(vault)).mockExtensionHash{ value: 1 }("");
    }

    function testDefaultHandler() public {
        bytes32 result = VaultExtensionMock(address(vault)).mockExtensionHash(bytes("V3"));
        assertEq(result, keccak256(bytes("V3")));
    }

    function testDefaultHandlerNonExistingFunction() public {
        vm.expectRevert();
        IRateProvider(address(vault)).getRate();
    }

    function testOnlyVault() public {
        // Does not revert via Vault
        assertTrue(IVault(address(vault)).isPoolRegistered(pool));

        IVault vaultExtension = IVault(vault.getVaultExtension());
        vm.expectRevert(abi.encodeWithSelector(NotVaultDelegateCall.selector));
        vaultExtension.isPoolRegistered(pool);
    }
}
