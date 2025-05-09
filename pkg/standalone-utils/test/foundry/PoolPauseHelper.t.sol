// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { IPoolHelperCommon } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IPoolHelperCommon.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";

import { PoolFactoryMock } from "@balancer-labs/v3-vault/contracts/test/PoolFactoryMock.sol";
import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";
import { PoolMock } from "@balancer-labs/v3-vault/contracts/test/PoolMock.sol";

import { PoolPauseHelper } from "../../contracts/PoolPauseHelper.sol";

contract PoolPauseHelperTest is BaseVaultTest {
    PoolPauseHelper pauseHelper;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        address[] memory owners = new address[](1);
        owners[0] = address(this);

        pauseHelper = new PoolPauseHelper(vault);

        authorizer.grantRole(pauseHelper.getActionId(pauseHelper.addPools.selector), address(this));
        authorizer.grantRole(pauseHelper.getActionId(pauseHelper.removePools.selector), address(this));
        authorizer.grantRole(pauseHelper.getActionId(pauseHelper.pausePools.selector), address(this));

        authorizer.grantRole(vault.getActionId(vault.pausePool.selector), address(pauseHelper));
    }

    function testAddPoolsWithTwoBatches() public {
        assertEq(pauseHelper.getPoolCount(), 0, "Initial pool count non-zero");

        // Add first batch of pools
        address[] memory firstPools = _generatePools(10);
        for (uint256 i = 0; i < firstPools.length; i++) {
            vm.expectEmit();
            emit IPoolHelperCommon.PoolAddedToSet(firstPools[i]);
        }

        pauseHelper.addPools(firstPools);

        assertEq(pauseHelper.getPoolCount(), firstPools.length, "Pools count should be 10");
        for (uint256 i = 0; i < firstPools.length; i++) {
            assertTrue(pauseHelper.hasPool(firstPools[i]));
        }

        // Add second batch of pools
        address[] memory secondPools = _generatePools(10);
        for (uint256 i = 0; i < secondPools.length; i++) {
            vm.expectEmit();
            emit IPoolHelperCommon.PoolAddedToSet(secondPools[i]);
        }

        pauseHelper.addPools(secondPools);
        assertEq(pauseHelper.getPoolCount(), firstPools.length + secondPools.length, "Pools count should be 20");

        for (uint256 i = 0; i < secondPools.length; i++) {
            assertTrue(pauseHelper.hasPool(secondPools[i]));
        }

        assertFalse(pauseHelper.hasPool(address(pauseHelper)), "Has invalid pool");
        assertFalse(pauseHelper.hasPool(address(0)), "Has zero address pool");
    }

    function testDoubleAddOnePool() public {
        assertEq(pauseHelper.getPoolCount(), 0, "Initial pool count non-zero");

        address[] memory pools = _generatePools(2);
        pools[1] = pools[0];

        vm.expectRevert(abi.encodeWithSelector(IPoolHelperCommon.PoolAlreadyInSet.selector, pools[1]));
        pauseHelper.addPools(pools);
    }

    function testAddPoolWithoutPermission() public {
        authorizer.revokeRole(pauseHelper.getActionId(pauseHelper.addPools.selector), address(this));

        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        pauseHelper.addPools(new address[](0));
    }

    function testRemovePools() public {
        assertEq(pauseHelper.getPoolCount(), 0, "Initial pool count non-zero");

        address[] memory pools = _addPools(10);
        assertEq(pauseHelper.getPoolCount(), 10, "Pools count should be 10");

        for (uint256 i = 0; i < pools.length; i++) {
            vm.expectEmit();
            emit IPoolHelperCommon.PoolRemovedFromSet(pools[i]);
        }

        pauseHelper.removePools(pools);

        assertEq(pauseHelper.getPoolCount(), 0, "End pool count non-zero");

        for (uint256 i = 0; i < pools.length; i++) {
            assertFalse(pauseHelper.hasPool(pools[i]));
        }
    }

    function testRemoveNotExistingPool() public {
        _addPools(10);

        vm.expectRevert(abi.encodeWithSelector(IPoolHelperCommon.PoolNotInSet.selector, address(0x00)));
        pauseHelper.removePools(new address[](1));
    }

    function testRemovePoolWithoutPermission() public {
        address[] memory pools = _addPools(10);

        authorizer.revokeRole(pauseHelper.getActionId(pauseHelper.removePools.selector), address(this));

        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        pauseHelper.removePools(pools);
    }

    function testPause() public {
        address[] memory pools = _addPools(10);

        pauseHelper.pausePools(pools);

        for (uint256 i = 0; i < pools.length; i++) {
            assertTrue(vault.isPoolPaused(pools[i]), "Pool should be paused");
        }
    }

    function testDoublePauseOnePool() public {
        address[] memory pools = _addPools(2);
        pools[1] = pools[0];

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.PoolPaused.selector, pools[1]));
        pauseHelper.pausePools(pools);
    }

    function testPauseIfPoolIsNotInList() public {
        _addPools(10);

        vm.expectRevert(abi.encodeWithSelector(IPoolHelperCommon.PoolNotInSet.selector, address(0x00)));
        pauseHelper.pausePools(new address[](1));
    }

    function testPauseWithoutPermission() public {
        address[] memory pools = _addPools(10);

        authorizer.revokeRole(pauseHelper.getActionId(pauseHelper.pausePools.selector), address(this));

        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        pauseHelper.pausePools(pools);
    }

    function testPauseWithoutVaultPermission() public {
        address[] memory pools = _addPools(1);

        authorizer.revokeRole(vault.getActionId(vault.pausePool.selector), address(pauseHelper));

        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        pauseHelper.pausePools(pools);
    }

    function testGetPools() public {
        address[] memory pools = _addPools(10);
        address[] memory storedPools = pauseHelper.getPools(0, 10);

        for (uint256 i = 0; i < pools.length; i++) {
            assertEq(pools[i], storedPools[i], "Stored pool should be the same as the added pool");
        }

        storedPools = pauseHelper.getPools(3, 5);

        for (uint256 i = 3; i < 5; i++) {
            assertEq(pools[i], storedPools[i - 3], "Stored pool should be the same as the added pool (partial)");
        }
    }

    function testGetPoolsEdgeCases() public {
        address[] memory pools = _addPools(10);
        address[] memory noPools = pauseHelper.getPools(5, 5);
        assertEq(noPools.length, 0, "No pools should be returned");

        address[] memory lastPool = pauseHelper.getPools(9, 10);
        assertEq(lastPool.length, 1, "Last pool length is incorrect");
        assertEq(pools[9], lastPool[0], "Last pool is incorrect");

        address[] memory firstPool = pauseHelper.getPools(0, 1);
        assertEq(firstPool.length, 1, "First pool length is incorrect");
        assertEq(pools[0], firstPool[0], "First pool is incorrect");
    }

    function testGetPoolsInvalidCases() public {
        uint256 poolsNum = 10;

        _addPools(poolsNum);
        vm.expectRevert(IPoolHelperCommon.IndexOutOfBounds.selector);
        pauseHelper.getPools(2, 1);

        vm.expectRevert(IPoolHelperCommon.IndexOutOfBounds.selector);
        pauseHelper.getPools(2, poolsNum + 1);

        vm.expectRevert(IPoolHelperCommon.IndexOutOfBounds.selector);
        pauseHelper.getPools(poolsNum, poolsNum);
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

        pauseHelper.addPools(pools);
    }
}
