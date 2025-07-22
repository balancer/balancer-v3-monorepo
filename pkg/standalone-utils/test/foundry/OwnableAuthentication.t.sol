// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";

import { OwnableAuthentication } from "../../contracts/OwnableAuthentication.sol";
import { OwnableAuthenticationMock } from "../../contracts/test/OwnableAuthenticationMock.sol";

contract OwnableAuthenticationTest is BaseVaultTest {
    OwnableAuthenticationMock internal authentication;
    address owner;

    function setUp() public virtual override {
        BaseVaultTest.setUp();
        owner = bob;

        authentication = new OwnableAuthenticationMock(vault, owner);

        authorizer.grantRole(
            IAuthentication(address(authentication)).getActionId(
                OwnableAuthenticationMock.permissionedFunction.selector
            ),
            admin
        );

        authorizer.grantRole(
            IAuthentication(address(authentication)).getActionId(OwnableAuthentication.forceTransferOwnership.selector),
            admin
        );
    }

    function testConstructor() external {
        vm.expectRevert(OwnableAuthentication.VaultNotSet.selector);
        new OwnableAuthentication(IVault(address(0)), bob);
    }

    function testGetVault() external view {
        assertEq(address(authentication.vault()), address(vault), "Vault address mismatch");
    }

    function testAuthorizer() external view {
        assertEq(
            address(authentication.getAuthorizer()),
            address(vault.getAuthorizer()),
            "Authorizer address mismatch"
        );
    }

    function testPermissionedFunctionOwner() external {
        // Does not revert.
        vm.prank(owner);
        authentication.permissionedFunction();
    }

    function testPermissionedFunctionGovernance() external {
        // Does not revert.
        vm.prank(admin);
        authentication.permissionedFunction();
    }

    function testPermissionedFunctionOther() external {
        vm.prank(alice);
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        authentication.permissionedFunction();
    }

    function testForceTransferOwnership() external {
        assertNotEq(authentication.owner(), alice, "Ownership already transferred");
        vm.prank(admin);
        authentication.forceTransferOwnership(alice);

        assertEq(authentication.owner(), alice, "Ownership not transferred to alice");
        assertEq(authentication.pendingOwner(), address(0), "Pending owner should be cleared");
    }

    function testForceTransferOwnershipOngoingTransfer() external {
        vm.prank(owner);
        authentication.transferOwnership(lp);
        assertEq(authentication.pendingOwner(), lp, "Pending owner should be lp");

        assertNotEq(authentication.owner(), alice, "Ownership already transferred to alice");
        assertNotEq(authentication.owner(), lp, "Ownership already transferred to lp");
        vm.prank(admin);
        authentication.forceTransferOwnership(alice);

        assertEq(authentication.owner(), alice, "Ownership not transferred to alice");
        assertEq(authentication.pendingOwner(), address(0), "Pending owner should be cleared");
    }

    function testForceTransferOwnershipByOwnerOrOther() external {
        vm.prank(owner);
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        authentication.forceTransferOwnership(alice);

        vm.prank(lp);
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        authentication.forceTransferOwnership(alice);
    }
}
