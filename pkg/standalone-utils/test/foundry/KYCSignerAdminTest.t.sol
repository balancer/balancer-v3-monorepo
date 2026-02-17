// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { IKYCSignerAdmin } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IKYCSignerAdmin.sol";

import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";

import { KYCSignerAdmin } from "../../contracts/KYCSignerAdmin.sol";

contract KYCSignerAdminTest is BaseVaultTest {
    KYCSignerAdmin internal signerAdmin;

    function setUp() public override {
        super.setUp();

        // admin is the owner; alice is the initial signer.
        signerAdmin = new KYCSignerAdmin(admin, alice);
    }

    /***************************************************************************
                                  Constructor
    ***************************************************************************/

    function testHasOwner() public view {
        assertEq(signerAdmin.owner(), admin);
    }

    function testHasSigner() public view {
        assertEq(signerAdmin.getKYCSigner(), alice);
    }

    function testEmitsEventOnDeployment() public {
        vm.expectEmit();
        emit IKYCSignerAdmin.KYCSignerSet(address(0), alice);

        new KYCSignerAdmin(admin, alice);
    }

    function testConstructorInvalidSigner() public {
        vm.expectRevert(IKYCSignerAdmin.KYCSignerCannotBeZero.selector);

        new KYCSignerAdmin(admin, address(0));
    }

    /***************************************************************************
                                    Setters
    ***************************************************************************/

    function testSetKYCSigner() public {
        vm.prank(admin);
        signerAdmin.setKYCSigner(bob);

        assertEq(signerAdmin.getKYCSigner(), bob);
    }

    function testSetKYCSignerEmitsEvent() public {
        vm.expectEmit();
        emit IKYCSignerAdmin.KYCSignerSet(alice, bob);

        vm.prank(admin);
        signerAdmin.setKYCSigner(bob);
    }

    function testSetKYCSignerNotOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, bob));

        vm.prank(bob);
        signerAdmin.setKYCSigner(bob);
    }

    function testSetInvalidKYCSigner() public {
        vm.expectRevert(IKYCSignerAdmin.KYCSignerCannotBeZero.selector);

        vm.prank(admin);
        signerAdmin.setKYCSigner(address(0));
    }

    function testSetKYCSignerMultipleTimes() public {
        vm.startPrank(admin);

        signerAdmin.setKYCSigner(bob);
        assertEq(signerAdmin.getKYCSigner(), bob);

        signerAdmin.setKYCSigner(lp);
        assertEq(signerAdmin.getKYCSigner(), lp);

        vm.stopPrank();
    }

    /***************************************************************************
                                  Ownership
    ***************************************************************************/

    function testOwnershipTransferTwoStep() public {
        vm.prank(admin);
        signerAdmin.transferOwnership(bob);

        // Pending owner should not be the owner yet.
        assertEq(signerAdmin.owner(), admin);
        assertEq(signerAdmin.pendingOwner(), bob);

        vm.prank(bob);
        signerAdmin.acceptOwnership();

        assertEq(signerAdmin.owner(), bob);
        assertEq(signerAdmin.pendingOwner(), address(0));
    }

    function testPendingOwnerCannotSetSigner() public {
        vm.prank(admin);
        signerAdmin.transferOwnership(bob);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, bob));

        vm.prank(bob);
        signerAdmin.setKYCSigner(lp);
    }

    function testNewOwnerCanSetSignerAfterAccepting() public {
        vm.prank(admin);
        signerAdmin.transferOwnership(bob);

        vm.prank(bob);
        signerAdmin.acceptOwnership();

        vm.prank(bob);
        signerAdmin.setKYCSigner(lp);

        assertEq(signerAdmin.getKYCSigner(), lp);
    }
}
