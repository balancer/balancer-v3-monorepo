// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { IPoolHelperCommon } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IPoolHelperCommon.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";

import { PoolPauseHelper } from "../../contracts/PoolPauseHelper.sol";
import { BasePoolHelperTest } from "./utils/BasePoolHelperTest.sol";

contract PoolPauseHelperTest is BasePoolHelperTest {
    function setUp() public virtual override {
        BasePoolHelperTest.setUp();

        // admin is the helper contract owner; alice is the "partner" manager of the pool set.
        poolHelper = new PoolPauseHelper(vault, admin);

        vm.prank(admin);
        alicePoolSetId = poolHelper.createPoolSet(alice);

        authorizer.grantRole(vault.getActionId(vault.pausePool.selector), address(poolHelper));
    }

    function testPause() public {
        address[] memory pools = _addPools(10);

        vm.prank(alice);
        PoolPauseHelper(address(poolHelper)).pausePools(pools);

        for (uint256 i = 0; i < pools.length; i++) {
            assertTrue(vault.isPoolPaused(pools[i]), "Pool should be paused");
        }
    }

    function testDoublePauseOnePool() public {
        address[] memory pools = _addPools(2);
        pools[1] = pools[0];

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.PoolPaused.selector, pools[1]));
        vm.prank(alice);
        PoolPauseHelper(address(poolHelper)).pausePools(pools);
    }

    function testPauseIfPoolIsNotInList() public {
        _addPools(10);

        vm.expectRevert(abi.encodeWithSelector(IPoolHelperCommon.PoolNotInSet.selector, address(0x00), alicePoolSetId));
        vm.prank(alice);
        PoolPauseHelper(address(poolHelper)).pausePools(new address[](1));
    }

    function testPauseWithoutPermission() public {
        address[] memory pools = _addPools(10);

        vm.expectRevert(IPoolHelperCommon.SenderIsNotPoolSetManager.selector);
        PoolPauseHelper(address(poolHelper)).pausePools(pools);
    }

    function testPauseWithoutVaultPermission() public {
        address[] memory pools = _addPools(1);

        authorizer.revokeRole(vault.getActionId(vault.pausePool.selector), address(poolHelper));

        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        vm.prank(alice);
        PoolPauseHelper(address(poolHelper)).pausePools(pools);
    }
}
