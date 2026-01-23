// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { BaseTest } from "@balancer-labs/v3-solidity-utils/test/foundry/utils/BaseTest.sol";

import { ClaimSignatureRegistry } from "../../contracts/ClaimSignatureRegistry.sol";

contract ClaimSignatureRegistryTest is BaseTest {
    ClaimSignatureRegistry private registry;

    function setUp() public override {
        super.setUp();
        registry = new ClaimSignatureRegistry();
    }

    function testRecordSignature() public {
        vm.startPrank(alice);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(aliceKey, registry.TERMS_DIGEST());
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectEmit();
        emit ClaimSignatureRegistry.SignatureRecorded(alice);

        registry.recordSignature(signature);
        vm.stopPrank();

        assertEq(keccak256(registry.signatures(alice)), keccak256(signature), "Signatures do not match");

        vm.expectRevert(abi.encodeWithSelector(ClaimSignatureRegistry.SignatureAlreadyRecorded.selector, alice));
        registry.recordSignatureFor(signature, alice);
    }

    function testRecordSignatureFail() public {
        vm.startPrank(alice);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(aliceKey, registry.TERMS_DIGEST());
        bytes memory signature = abi.encodePacked(r, s, v);
        vm.stopPrank();

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(ClaimSignatureRegistry.InvalidSignature.selector, bob));
        registry.recordSignature(signature);
    }

    function testRecordSignatureFor() public {
        vm.startPrank(alice);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(aliceKey, registry.TERMS_DIGEST());
        bytes memory signature = abi.encodePacked(r, s, v);
        vm.stopPrank();

        vm.expectEmit();
        emit ClaimSignatureRegistry.SignatureRecorded(alice);
        registry.recordSignatureFor(signature, alice);

        assertEq(keccak256(registry.signatures(alice)), keccak256(signature), "Signatures do not match");

        vm.expectRevert(abi.encodeWithSelector(ClaimSignatureRegistry.SignatureAlreadyRecorded.selector, alice));
        registry.recordSignatureFor(signature, alice);
    }

    function testRecordSignatureForFail() public {
        vm.startPrank(alice);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(aliceKey, registry.TERMS_DIGEST());
        bytes memory signature = abi.encodePacked(r, s, v);
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(ClaimSignatureRegistry.InvalidSignature.selector, bob));
        registry.recordSignatureFor(signature, bob);

        vm.expectRevert(ClaimSignatureRegistry.InvalidSigner.selector);
        registry.recordSignatureFor(signature, address(0));
    }
}
