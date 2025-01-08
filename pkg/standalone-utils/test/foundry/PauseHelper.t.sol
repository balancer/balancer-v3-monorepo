// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import { PoolMock } from "@balancer-labs/v3-vault/contracts/test/PoolMock.sol";
import { PoolFactoryMock } from "@balancer-labs/v3-vault/contracts/test/PoolFactoryMock.sol";
import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";
import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";

import { PauseHelper } from "../../contracts/PauseHelper.sol";

contract PauseHelperTest is BaseVaultTest {
    PauseHelper pauseHelper;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        address[] memory owners = new address[](1);
        owners[0] = address(this);

        pauseHelper = new PauseHelper(vault);

        authorizer.grantRole(pauseHelper.getActionId(pauseHelper.addPools.selector), address(this));
        authorizer.grantRole(pauseHelper.getActionId(pauseHelper.removePools.selector), address(this));
        authorizer.grantRole(pauseHelper.getActionId(pauseHelper.pause.selector), address(this));

        authorizer.grantRole(vault.getActionId(vault.pausePool.selector), address(pauseHelper));
    }

    function testAddPoolsWithTwoBatches() public {
        address[] memory firstPools = _addPools(10);
        assertEq(pauseHelper.getPoolsCount(), firstPools.length, "Pools count should be 10");

        address[] memory secondPools = _addPools(10);
        assertEq(pauseHelper.getPoolsCount(), firstPools.length + secondPools.length, "Pools count should be 20");

        for (uint256 i = 0; i < firstPools.length; i++) {
            assertTrue(pauseHelper.hasPool(firstPools[i]));
        }

        for (uint256 i = 0; i < secondPools.length; i++) {
            assertTrue(pauseHelper.hasPool(secondPools[i]));
        }
    }

    function testAddPoolWithoutPermission() public {
        authorizer.revokeRole(pauseHelper.getActionId(pauseHelper.addPools.selector), address(this));

        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        pauseHelper.addPools(new address[](0));
    }

    function testRemovePools() public {
        address[] memory pools = _addPools(10);
        assertEq(pauseHelper.getPoolsCount(), 10, "Pools count should be 10");

        for (uint256 i = 0; i < pools.length; i++) {
            vm.expectEmit();
            emit PauseHelper.PoolRemoved(pools[i]);
        }

        pauseHelper.removePools(pools);

        assertEq(pauseHelper.getPoolsCount(), 0, "Pools count should be 0");

        for (uint256 i = 0; i < pools.length; i++) {
            assertFalse(pauseHelper.hasPool(pools[i]));
        }
    }

    function testRemovePoolWithoutPermission() public {
        address[] memory pools = _addPools(10);

        authorizer.revokeRole(pauseHelper.getActionId(pauseHelper.removePools.selector), address(this));

        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        pauseHelper.removePools(pools);
    }

    function testPause() public {
        address[] memory pools = _addPools(10);

        pauseHelper.pause(pools);

        for (uint256 i = 0; i < pools.length; i++) {
            assertTrue(vault.isPoolPaused(pools[i]), "Pool should be paused");
        }
    }

    function testPauseWithoutPermission() public {
        address[] memory pools = _addPools(10);

        authorizer.revokeRole(pauseHelper.getActionId(pauseHelper.pause.selector), address(this));

        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        pauseHelper.pause(pools);
    }

    function testPauseIfPoolIsNotInList() public {
        _addPools(10);

        vm.expectRevert("Pool is not in the list of pools");
        pauseHelper.pause(new address[](1));
    }

    function testGetPools() public {
        address[] memory pools = _addPools(10);
        address[] memory storedPools = pauseHelper.getPools(0, 10);

        for (uint256 i = 0; i < pools.length; i++) {
            assertEq(pools[i], storedPools[i], "Stored pool should be the same as the added pool");
        }
    }

    function _addPools(uint256 length) internal returns (address[] memory pools) {
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

        for (uint256 i = 0; i < pools.length; i++) {
            vm.expectEmit();
            emit PauseHelper.PoolAdded(pools[i]);
        }

        pauseHelper.addPools(pools);
    }
}
