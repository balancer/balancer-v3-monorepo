// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { IPoolHelperCommon } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IPoolHelperCommon.sol";

import { PoolHelperMock } from "../../contracts/test/PoolHelperMock.sol";
import { BasePoolHelperTest } from "./utils/BasePoolHelperTest.sol";

contract PoolHelperCommonTest is BasePoolHelperTest {
    address constant ANY_ADDRESS = address(0xdeadbeef);

    function testInvalidInitialOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new PoolHelperMock(vault, address(0));
    }

    function testCreatePoolSetInvalidManager() public {
        // Manager cannot be the zero address.
        vm.expectRevert(IPoolHelperCommon.InvalidPoolSetManager.selector);
        vm.prank(admin);
        poolHelper.createPoolSet(address(0));

        // We already have a pool set managed by alice, so cannot create a second one.
        vm.expectRevert(abi.encodeWithSelector(IPoolHelperCommon.PoolSetManagerNotUnique.selector, alice));
        vm.prank(admin);
        poolHelper.createPoolSet(alice);
    }

    function testCreatePoolSetPermissioned() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, lp));
        vm.prank(lp);
        poolHelper.createPoolSet(lp);
    }

    function testCreatePoolSetEvents() public {
        uint256 expectedPoolSetId = poolHelper.getNextPoolSetId();

        vm.expectEmit();
        emit IPoolHelperCommon.PoolSetCreated(expectedPoolSetId, admin);

        vm.prank(admin);
        uint256 actualPoolSetId = poolHelper.createPoolSet(admin);

        assertEq(actualPoolSetId, expectedPoolSetId, "Wrong poolSetId (plain)");

        // Create with initial pools
        uint256 numPools = 3;

        address[] memory pools = _generatePools(numPools);

        expectedPoolSetId++;

        vm.expectEmit();
        emit IPoolHelperCommon.PoolSetCreated(expectedPoolSetId, lp);

        for (uint256 i = 0; i < numPools; ++i) {
            vm.expectEmit();
            emit IPoolHelperCommon.PoolAddedToSet(pools[i], expectedPoolSetId);
        }

        vm.prank(admin);
        actualPoolSetId = poolHelper.createPoolSet(lp, pools);

        assertEq(actualPoolSetId, expectedPoolSetId, "Wrong poolSetId (with pools)");

        uint256 poolCount = poolHelper.getPoolCountForSet(actualPoolSetId);
        assertEq(poolCount, numPools, "Wrong pool count");

        bool hasPool = poolHelper.isPoolInSet(address(0), actualPoolSetId);
        assertFalse(hasPool, "Should not have zero address");

        for (uint256 i = 0; i < numPools; ++i) {
            hasPool = poolHelper.isPoolInSet(pools[i], actualPoolSetId);
            assertTrue(hasPool, "Set does not contain expected pool");
        }
    }

    function testDestroyPoolSetWithPools() public {
        // Since event order isn't guaranteed, need to test this with a single pool.
        address[] memory pools = _generatePools(1);

        vm.prank(admin);
        uint256 poolSetId = poolHelper.createPoolSet(admin, pools);

        // Now destroy, and make sure we get the remove event for the pool.
        vm.expectEmit();
        emit IPoolHelperCommon.PoolRemovedFromSet(pools[0], poolSetId);

        vm.prank(admin);
        poolHelper.destroyPoolSet(poolSetId);
    }

    function testGetPoolSetIdForCaller() public {
        vm.prank(alice);
        uint256 poolSetId = poolHelper.getPoolSetIdForCaller();
        assertEq(poolSetId, alicePoolSetId, "Wrong poolSetId for alice");

        vm.prank(bob);
        poolSetId = poolHelper.getPoolSetIdForCaller();
        assertEq(poolSetId, bobPoolSetId, "Wrong poolSetId for bob");

        poolSetId = poolHelper.getPoolSetIdForCaller();
        assertEq(poolSetId, 0, "PoolSetId should be 0");
    }

    function testGetPoolSetIdForManager() public view {
        uint256 poolSetId = poolHelper.getPoolSetIdForManager(alice);
        assertEq(poolSetId, alicePoolSetId, "Wrong poolSetId for alice");

        poolSetId = poolHelper.getPoolSetIdForManager(bob);
        assertEq(poolSetId, bobPoolSetId, "Wrong poolSetId for bob");

        poolSetId = poolHelper.getPoolSetIdForManager(lp);
        assertEq(poolSetId, 0, "PoolSetId should be 0");
    }

    function testGetManagerForPoolSetId() public view {
        address manager = poolHelper.getManagerForPoolSet(alicePoolSetId);
        assertEq(manager, alice, "Wrong manager for alicePoolSetId");

        manager = poolHelper.getManagerForPoolSet(bobPoolSetId);
        assertEq(manager, bob, "Wrong manager for bobPoolSetId");

        manager = poolHelper.getManagerForPoolSet(45);
        assertEq(manager, address(0), "Manager should be 0");
    }

    function testPoolCountForSetErrors() public {
        uint256 poolCount = poolHelper.getPoolCountForSet(alicePoolSetId);
        assertEq(poolCount, 0, "Alice's pool set should have no pools");

        vm.expectRevert(abi.encodeWithSelector(IPoolHelperCommon.InvalidPoolSetId.selector, 0));
        poolHelper.getPoolCountForSet(0);

        vm.expectRevert(abi.encodeWithSelector(IPoolHelperCommon.InvalidPoolSetId.selector, 100));
        poolHelper.getPoolCountForSet(100);
    }

    function testSetHasPoolErrors() public {
        bool hasPool = poolHelper.isPoolInSet(ANY_ADDRESS, alicePoolSetId);
        assertFalse(hasPool, "Alice's pool set should not have a random pool");

        vm.expectRevert(abi.encodeWithSelector(IPoolHelperCommon.InvalidPoolSetId.selector, 0));
        poolHelper.isPoolInSet(ANY_ADDRESS, 0);

        vm.expectRevert(abi.encodeWithSelector(IPoolHelperCommon.InvalidPoolSetId.selector, 100));
        poolHelper.isPoolInSet(ANY_ADDRESS, 100);
    }

    function testDestroyPoolSetPermissions() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, lp));
        vm.prank(lp);
        poolHelper.destroyPoolSet(alicePoolSetId);
    }

    function testDestroyPoolSetErrors() public {
        vm.expectRevert(abi.encodeWithSelector(IPoolHelperCommon.InvalidPoolSetId.selector, 0));
        vm.prank(admin);
        poolHelper.destroyPoolSet(0);

        vm.expectRevert(abi.encodeWithSelector(IPoolHelperCommon.InvalidPoolSetId.selector, 100));
        vm.prank(admin);
        poolHelper.destroyPoolSet(100);
    }

    function testDestroyPoolSetEvents() public {
        vm.expectEmit();
        emit IPoolHelperCommon.PoolSetDestroyed(alicePoolSetId, alice);

        vm.prank(alice);
        uint256 poolSetId = poolHelper.getPoolSetIdForCaller();
        assertEq(poolSetId, alicePoolSetId, "Wrong poolSetId for alice");

        // `poolSetId` will get overwritten later.
        uint256 originalPoolSetId = poolSetId;

        vm.prank(admin);
        poolHelper.destroyPoolSet(alicePoolSetId);

        // She should be removed as a manager
        vm.prank(alice);
        poolSetId = poolHelper.getPoolSetIdForCaller();
        assertEq(poolSetId, 0, "alice still a manager");

        address manager = poolHelper.getManagerForPoolSet(originalPoolSetId);
        assertEq(manager, address(0), "Destroyed poolSetId still has a manager");

        // Set should be gone
        vm.expectRevert(abi.encodeWithSelector(IPoolHelperCommon.InvalidPoolSetId.selector, alicePoolSetId));
        poolHelper.getPoolCountForSet(alicePoolSetId);
    }

    function testTransferPoolOwnershipErrors() public {
        // Only existing managers can transfer.
        vm.expectRevert(IPoolHelperCommon.SenderIsNotPoolSetManager.selector);
        poolHelper.transferPoolSetOwnership(lp);

        // Cannot transfer to zero address.
        vm.expectRevert(IPoolHelperCommon.InvalidPoolSetManager.selector);
        vm.prank(alice);
        poolHelper.transferPoolSetOwnership(address(0));

        // Cannot transfer to existing manager.
        vm.expectRevert(abi.encodeWithSelector(IPoolHelperCommon.PoolSetManagerNotUnique.selector, bob));
        vm.prank(alice);
        poolHelper.transferPoolSetOwnership(bob);
    }

    function testTransferPoolOwnership() public {
        vm.expectEmit();
        emit IPoolHelperCommon.PoolSetOwnershipTransferred(alicePoolSetId, alice, lp);

        vm.prank(alice);
        poolHelper.transferPoolSetOwnership(lp);

        // Verify that it worked.
        vm.prank(alice);
        uint256 aliceId = poolHelper.getPoolSetIdForCaller();
        assertEq(aliceId, 0, "Alice still has a pool set");

        vm.prank(lp);
        uint256 poolSetId = poolHelper.getPoolSetIdForCaller();
        assertEq(poolSetId, alicePoolSetId, "Pool set not transferred");

        address manager = poolHelper.getManagerForPoolSet(poolSetId);
        assertEq(manager, lp, "Manager address not transferred");
    }

    function testIsValidPoolSetId() public view {
        assertTrue(poolHelper.isValidPoolSetId(alicePoolSetId), "Alice's pool set id not valid");
        assertTrue(poolHelper.isValidPoolSetId(bobPoolSetId), "Bob's pool set id not valid");

        assertFalse(poolHelper.isValidPoolSetId(45), "PoolSetId should not be valid");
    }
}
