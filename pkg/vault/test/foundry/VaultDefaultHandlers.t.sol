// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { VaultExtensionMock } from "../../contracts/test/VaultExtensionMock.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

interface IRandom {
    function nonexistentFunction() external payable;
}

contract VaultDefaultHandlersTest is BaseVaultTest {
    using Address for address payable;

    function setUp() public virtual override {
        BaseVaultTest.setUp();
    }

    function testReceiveVault() public {
        vm.prank(alice);
        vm.expectRevert(IVaultErrors.CannotReceiveEth.selector);
        payable(address(vault)).transfer(1);
    }

    function testReceiveVaultExtension() public {
        vm.prank(alice);
        vm.expectRevert(IVaultErrors.CannotReceiveEth.selector);
        payable(address(vaultExtension)).transfer(1);
    }

    function testReceiveVaultAdmin() public {
        vm.prank(alice);
        vm.expectRevert(IVaultErrors.CannotReceiveEth.selector);
        payable(address(vaultAdmin)).transfer(1);
    }

    function testDefaultHandlerWithEth() public {
        vm.prank(alice);
        vm.expectRevert(IVaultErrors.CannotReceiveEth.selector);
        VaultExtensionMock(payable(address(vault))).mockExtensionHash{ value: 1 }(bytes(""));
    }

    function testDefaultHandler() public {
        bytes32 result = VaultExtensionMock(payable(address(vault))).mockExtensionHash(bytes("v3"));
        assertEq(result, keccak256(bytes("v3")));
    }

    function testDefaultHandlerNonExistentFunction() public {
        vm.expectRevert();
        IRateProvider(address(vault)).getRate();
    }

    function testOnlyVault() public {
        // Does not revert via Vault.
        assertTrue(IVault(address(vault)).isPoolRegistered(pool));

        IVault vaultExtension = IVault(vault.getVaultExtension());
        vm.expectRevert(IVaultErrors.NotVaultDelegateCall.selector);
        vaultExtension.isPoolRegistered(pool);
    }

    function testSendEthNowhereExtension() public {
        // Try sending ETH directly to the VaultExtension.
        vm.expectRevert(IVaultErrors.CannotReceiveEth.selector);
        IRandom(address(vaultExtension)).nonexistentFunction{ value: 1 }();
    }

    function testSendEthNowhereAdmin() public {
        // Try sending ETH directly to the VaultAdmin.
        vm.expectRevert(IVaultErrors.CannotReceiveEth.selector);
        IRandom(address(vaultAdmin)).nonexistentFunction{ value: 1 }();
    }

    function testAdminFallback() public {
        // Try calling an non-existent function on the VaultAdmin.
        vm.expectRevert("Not implemented");
        IRandom(address(vaultAdmin)).nonexistentFunction();
    }
}
