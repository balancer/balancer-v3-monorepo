// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";

import { IPoolHelperCommon } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IPoolHelperCommon.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";

import { PoolFactoryMock } from "@balancer-labs/v3-vault/contracts/test/PoolFactoryMock.sol";

import { PoolHelperMock } from "../../../contracts/test/PoolHelperMock.sol";

// Common test contract for Pool Helpers.
abstract contract BasePoolHelperTest is BaseVaultTest {
    IPoolHelperCommon internal poolHelper;
    uint256 internal alicePoolSetId;
    uint256 internal bobPoolSetId;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        // admin is the owner of the helper contract.
        poolHelper = new PoolHelperMock(vault, admin);

        vm.startPrank(admin);
        alicePoolSetId = poolHelper.createPoolSet(alice);
        bobPoolSetId = poolHelper.createPoolSet(bob);
        vm.stopPrank();
    }

    function testAddPoolsWithTwoBatches() public {
        assertEq(poolHelper.getPoolCountForSet(alicePoolSetId), 0, "Initial pool count non-zero");

        // Add first batch of pools
        address[] memory firstPools = _generatePools(10);
        for (uint256 i = 0; i < firstPools.length; i++) {
            vm.expectEmit();
            emit IPoolHelperCommon.PoolAddedToSet(firstPools[i], alicePoolSetId);
        }

        vm.prank(admin);
        poolHelper.addPoolsToSet(alicePoolSetId, firstPools);

        assertEq(poolHelper.getPoolCountForSet(alicePoolSetId), firstPools.length, "Pools count should be 10");
        for (uint256 i = 0; i < firstPools.length; i++) {
            assertTrue(poolHelper.isPoolInSet(firstPools[i], alicePoolSetId));
        }

        // Add second batch of pools
        address[] memory secondPools = _generatePools(10);
        for (uint256 i = 0; i < secondPools.length; i++) {
            vm.expectEmit();
            emit IPoolHelperCommon.PoolAddedToSet(secondPools[i], alicePoolSetId);
        }

        vm.prank(admin);
        poolHelper.addPoolsToSet(alicePoolSetId, secondPools);
        assertEq(
            poolHelper.getPoolCountForSet(alicePoolSetId),
            firstPools.length + secondPools.length,
            "Pools count should be 20"
        );

        for (uint256 i = 0; i < secondPools.length; i++) {
            assertTrue(poolHelper.isPoolInSet(secondPools[i], alicePoolSetId));
        }

        assertFalse(poolHelper.isPoolInSet(address(poolHelper), alicePoolSetId), "Has invalid pool");
        assertFalse(poolHelper.isPoolInSet(address(0), alicePoolSetId), "Has zero address pool");
    }

    function testDoubleAddOnePool() public {
        assertEq(poolHelper.getPoolCountForSet(alicePoolSetId), 0, "Initial pool count non-zero");

        address[] memory pools = _addPools(2);
        pools[1] = pools[0];

        vm.expectRevert(abi.encodeWithSelector(IPoolHelperCommon.PoolAlreadyInSet.selector, pools[1], alicePoolSetId));
        vm.prank(admin);
        poolHelper.addPoolsToSet(alicePoolSetId, pools);
    }

    function testAddPoolWithoutPermission() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, lp));
        vm.prank(lp);
        poolHelper.addPoolsToSet(alicePoolSetId, new address[](0));
    }

    function testRemovePools() public {
        assertEq(poolHelper.getPoolCountForSet(alicePoolSetId), 0, "Initial pool count non-zero");

        address[] memory pools = _addPools(10);
        assertEq(poolHelper.getPoolCountForSet(alicePoolSetId), 10, "Pools count should be 10");

        for (uint256 i = 0; i < pools.length; i++) {
            vm.expectEmit();
            emit IPoolHelperCommon.PoolRemovedFromSet(pools[i], alicePoolSetId);
        }

        vm.prank(admin);
        poolHelper.removePoolsFromSet(alicePoolSetId, pools);

        assertEq(poolHelper.getPoolCountForSet(alicePoolSetId), 0, "End pool count non-zero");

        for (uint256 i = 0; i < pools.length; i++) {
            assertFalse(poolHelper.isPoolInSet(pools[i], alicePoolSetId));
        }
    }

    function testRemoveNonexistentPool() public {
        _addPools(10);

        vm.expectRevert(abi.encodeWithSelector(IPoolHelperCommon.PoolNotInSet.selector, address(0x00), alicePoolSetId));
        vm.prank(admin);
        poolHelper.removePoolsFromSet(alicePoolSetId, new address[](1));
    }

    function testRemovePoolWithoutPermission() public {
        address[] memory pools = _addPools(10);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, lp));
        vm.prank(lp);
        poolHelper.removePoolsFromSet(alicePoolSetId, pools);
    }

    function testGetPools() public {
        address[] memory pools = _addPools(10);
        address[] memory storedPools = poolHelper.getPoolsInSet(alicePoolSetId, 0, 10);

        for (uint256 i = 0; i < pools.length; i++) {
            assertEq(pools[i], storedPools[i], "Stored pool should be the same as the added pool");
        }

        storedPools = poolHelper.getPoolsInSet(alicePoolSetId, 3, 5);

        for (uint256 i = 3; i < 5; i++) {
            assertEq(pools[i], storedPools[i - 3], "Stored pool should be the same as the added pool (partial)");
        }
    }

    function testGetAllPools() public {
        address[] memory pools = _addPools(10);
        address[] memory storedPools = poolHelper.getAllPoolsInSet(alicePoolSetId);

        for (uint256 i = 0; i < pools.length; i++) {
            assertEq(pools[i], storedPools[i], "Stored pool should be the same as the added pool");
        }
    }

    function testGetPoolsEdgeCases() public {
        address[] memory pools = _addPools(10);

        address[] memory noPools = poolHelper.getPoolsInSet(alicePoolSetId, 5, 5);
        assertEq(noPools.length, 0, "No pools should be returned");

        address[] memory lastPool = poolHelper.getPoolsInSet(alicePoolSetId, 9, 10);
        assertEq(lastPool.length, 1, "Last pool length is incorrect");
        assertEq(pools[9], lastPool[0], "Last pool is incorrect");

        address[] memory firstPool = poolHelper.getPoolsInSet(alicePoolSetId, 0, 1);
        assertEq(firstPool.length, 1, "First pool length is incorrect");
        assertEq(pools[0], firstPool[0], "First pool is incorrect");
    }

    function testGetPoolsInvalidCases() public {
        uint256 poolsNum = 10;

        _addPools(poolsNum);

        vm.expectRevert(abi.encodeWithSelector(IPoolHelperCommon.IndexOutOfBounds.selector, alicePoolSetId));
        poolHelper.getPoolsInSet(alicePoolSetId, 2, 1);

        vm.expectRevert(abi.encodeWithSelector(IPoolHelperCommon.IndexOutOfBounds.selector, alicePoolSetId));
        poolHelper.getPoolsInSet(alicePoolSetId, 2, poolsNum + 1);

        vm.expectRevert(abi.encodeWithSelector(IPoolHelperCommon.IndexOutOfBounds.selector, alicePoolSetId));
        poolHelper.getPoolsInSet(alicePoolSetId, poolsNum, poolsNum);
    }

    function testAddUnregisteredPool() public {
        address[] memory invalidAddresses = new address[](1);
        invalidAddresses[0] = address(0x1234);

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.PoolNotRegistered.selector, invalidAddresses[0]));
        vm.prank(admin);
        poolHelper.addPoolsToSet(alicePoolSetId, invalidAddresses);
    }

    function _generatePools(uint256 length) internal returns (address[] memory pools) {
        pools = new address[](length);
        for (uint256 i = 0; i < length; i++) {
            pools[i] = PoolFactoryMock(poolFactory).createPool("Test", "TEST");
            PoolFactoryMock(poolFactory).registerTestPool(
                pools[i],
                vault.buildTokenConfig(tokens),
                poolHooksContract,
                lp
            );
        }
    }

    function _addPools(uint256 length) internal returns (address[] memory pools) {
        pools = _generatePools(length);

        vm.prank(admin);
        poolHelper.addPoolsToSet(alicePoolSetId, pools);
    }
}
