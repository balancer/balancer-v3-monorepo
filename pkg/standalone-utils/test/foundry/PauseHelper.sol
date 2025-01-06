// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import { Safe } from "@safe-global/safe-contracts/contracts/Safe.sol";

import { PoolMock } from "@balancer-labs/v3-vault/contracts/test/PoolMock.sol";
import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";

import { PauseHelper } from "../../contracts/PauseHelper.sol";

contract PauseHelperTest is BaseVaultTest {
    PauseHelper pauseHelper;

    address payable safeMock = payable(address(0x1));

    function setUp() public virtual override {
        BaseVaultTest.setUp();
        pauseHelper = new PauseHelper(vault, Safe(safeMock));

        authorizer.grantRole(pauseHelper.getActionId(pauseHelper.addPools.selector), address(this));
        authorizer.grantRole(pauseHelper.getActionId(pauseHelper.removePools.selector), address(this));
    }

    function testAddPools() public {
        address[] memory pools = _addPools(10);

        assertEq(pauseHelper.getPoolsCount(), pools.length);

        for (uint256 i = 0; i < pools.length; i++) {
            assertTrue(pauseHelper.hasPool(pools[i]));
        }
    }

    function testRemovePools() public {
        address[] memory pools = _addPools(10);
        assertEq(pauseHelper.getPoolsCount(), 10);

        for (uint256 i = 0; i < pools.length; i++) {
            vm.expectEmit();
            emit PauseHelper.PoolRemoved(pools[i]);
        }

        pauseHelper.removePools(pools);

        assertEq(pauseHelper.getPoolsCount(), 0);

        for (uint256 i = 0; i < pools.length; i++) {
            assertFalse(pauseHelper.hasPool(pools[i]));
        }
    }

    function _addPools(uint256 length) internal returns (address[] memory pools) {
        pools = new address[](length);
        for (uint256 i = 0; i < length; i++) {
            pools[i] = address(new PoolMock(vault, "Test", "TEST"));

            vm.expectEmit();
            emit PauseHelper.PoolAdded(pools[i]);
        }

        pauseHelper.addPools(pools);
    }
}
