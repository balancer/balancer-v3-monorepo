// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { IPoolSwapFeeHelper } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IPoolSwapFeeHelper.sol";
import { IPoolHelperCommon } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IPoolHelperCommon.sol";
import { PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";

import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";
import { PoolFactoryMock } from "@balancer-labs/v3-vault/contracts/test/PoolFactoryMock.sol";
import { PoolMock } from "@balancer-labs/v3-vault/contracts/test/PoolMock.sol";

import { PoolSwapFeeHelper } from "../../contracts/PoolSwapFeeHelper.sol";

contract PoolSwapFeeHelperTest is BaseVaultTest {
    uint256 constant NEW_SWAP_FEE_PERCENTAGE = 1.346e16;

    PoolSwapFeeHelper internal feeHelper;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        feeHelper = new PoolSwapFeeHelper(vault);

        authorizer.grantRole(feeHelper.getActionId(feeHelper.addPools.selector), address(this));
        authorizer.grantRole(feeHelper.getActionId(feeHelper.removePools.selector), address(this));
        authorizer.grantRole(feeHelper.getActionId(feeHelper.setStaticSwapFeePercentage.selector), address(this));

        authorizer.grantRole(vault.getActionId(vault.setStaticSwapFeePercentage.selector), address(feeHelper));
    }

    function testAddPoolsWithTwoBatches() public {
        assertEq(feeHelper.getPoolCount(), 0, "Initial pool count non-zero");

        // Add first batch of pools
        address[] memory firstPools = _generatePools(10);
        for (uint256 i = 0; i < firstPools.length; i++) {
            vm.expectEmit();
            emit IPoolHelperCommon.PoolAddedToSet(firstPools[i]);
        }

        feeHelper.addPools(firstPools);

        assertEq(feeHelper.getPoolCount(), firstPools.length, "Pools count should be 10");
        for (uint256 i = 0; i < firstPools.length; i++) {
            assertTrue(feeHelper.hasPool(firstPools[i]));
        }

        // Add second batch of pools
        address[] memory secondPools = _generatePools(10);
        for (uint256 i = 0; i < secondPools.length; i++) {
            vm.expectEmit();
            emit IPoolHelperCommon.PoolAddedToSet(secondPools[i]);
        }

        feeHelper.addPools(secondPools);
        assertEq(feeHelper.getPoolCount(), firstPools.length + secondPools.length, "Pools count should be 20");

        for (uint256 i = 0; i < secondPools.length; i++) {
            assertTrue(feeHelper.hasPool(secondPools[i]));
        }

        assertFalse(feeHelper.hasPool(address(feeHelper)), "Has invalid pool");
        assertFalse(feeHelper.hasPool(address(0)), "Has zero address pool");
    }

    function testDoubleAddOnePool() public {
        assertEq(feeHelper.getPoolCount(), 0, "Initial pool count non-zero");

        address[] memory pools = _addPools(2);
        pools[1] = pools[0];

        vm.expectRevert(abi.encodeWithSelector(IPoolHelperCommon.PoolAlreadyInSet.selector, pools[1]));
        feeHelper.addPools(pools);
    }

    function testAddPoolWithoutPermission() public {
        authorizer.revokeRole(feeHelper.getActionId(feeHelper.addPools.selector), address(this));

        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        feeHelper.addPools(new address[](0));
    }

    function testAddPoolWithSwapManager() public {
        address[] memory pools = new address[](1);

        pools[0] = PoolFactoryMock(poolFactory).createPool("Test", "TEST");
        PoolRoleAccounts memory roleAccounts;
        roleAccounts.swapFeeManager = alice;

        PoolFactoryMock(poolFactory).registerGeneralTestPool(
            pools[0],
            vault.buildTokenConfig(tokens),
            1e16, // swap fee
            0, // pause window duration
            false, // protocol fee exempt
            roleAccounts,
            poolHooksContract
        );

        vm.expectRevert(abi.encodeWithSelector(IPoolSwapFeeHelper.PoolHasSwapManager.selector, pools[0]));
        feeHelper.addPools(pools);
    }

    function testRemovePools() public {
        assertEq(feeHelper.getPoolCount(), 0, "Initial pool count non-zero");

        address[] memory pools = _addPools(10);
        assertEq(feeHelper.getPoolCount(), 10, "Pools count should be 10");

        for (uint256 i = 0; i < pools.length; i++) {
            vm.expectEmit();
            emit IPoolHelperCommon.PoolRemovedFromSet(pools[i]);
        }

        feeHelper.removePools(pools);

        assertEq(feeHelper.getPoolCount(), 0, "End pool count non-zero");

        for (uint256 i = 0; i < pools.length; i++) {
            assertFalse(feeHelper.hasPool(pools[i]));
        }
    }

    function testRemoveNotExistingPool() public {
        _addPools(10);

        vm.expectRevert(abi.encodeWithSelector(IPoolHelperCommon.PoolNotInSet.selector, address(0x00)));
        feeHelper.removePools(new address[](1));
    }

    function testRemovePoolWithoutPermission() public {
        address[] memory pools = _addPools(10);

        authorizer.revokeRole(feeHelper.getActionId(feeHelper.removePools.selector), address(this));

        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        feeHelper.removePools(pools);
    }

    function testSetSwapFee() public {
        address[] memory pools = _addPools(10);

        for (uint256 i = 0; i < pools.length; ++i) {
            feeHelper.setStaticSwapFeePercentage(pools[i], NEW_SWAP_FEE_PERCENTAGE);
        }

        for (uint256 i = 0; i < pools.length; i++) {
            uint256 swapFeePercentage = vault.getStaticSwapFeePercentage(pools[i]);

            assertEq(swapFeePercentage, NEW_SWAP_FEE_PERCENTAGE, "Wrong swap fee percentage");
        }
    }

    function testSetSwapFeeIfPoolIsNotInList() public {
        _addPools(10);

        vm.expectRevert(abi.encodeWithSelector(IPoolHelperCommon.PoolNotInSet.selector, address(0x00)));
        feeHelper.setStaticSwapFeePercentage(address(0), NEW_SWAP_FEE_PERCENTAGE);
    }

    function testSetSwapFeeWithoutPermission() public {
        address[] memory pools = _addPools(1);

        authorizer.revokeRole(feeHelper.getActionId(feeHelper.setStaticSwapFeePercentage.selector), address(this));

        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        feeHelper.setStaticSwapFeePercentage(pools[0], NEW_SWAP_FEE_PERCENTAGE);
    }

    function testGetPools() public {
        address[] memory pools = _addPools(10);
        address[] memory storedPools = feeHelper.getPools(0, 10);

        for (uint256 i = 0; i < pools.length; i++) {
            assertEq(pools[i], storedPools[i], "Stored pool should be the same as the added pool");
        }

        storedPools = feeHelper.getPools(3, 5);

        for (uint256 i = 3; i < 5; i++) {
            assertEq(pools[i], storedPools[i - 3], "Stored pool should be the same as the added pool (partial)");
        }
    }

    function testGetPoolsEdgeCases() public {
        address[] memory pools = _addPools(10);
        address[] memory noPools = feeHelper.getPools(5, 5);
        assertEq(noPools.length, 0, "No pools should be returned");

        address[] memory lastPool = feeHelper.getPools(9, 10);
        assertEq(lastPool.length, 1, "Last pool length is incorrect");
        assertEq(pools[9], lastPool[0], "Last pool is incorrect");

        address[] memory firstPool = feeHelper.getPools(0, 1);
        assertEq(firstPool.length, 1, "First pool length is incorrect");
        assertEq(pools[0], firstPool[0], "First pool is incorrect");
    }

    function testGetPoolsInvalidCases() public {
        uint256 poolsNum = 10;

        _addPools(poolsNum);
        vm.expectRevert(IPoolHelperCommon.IndexOutOfBounds.selector);
        feeHelper.getPools(2, 1);

        vm.expectRevert(IPoolHelperCommon.IndexOutOfBounds.selector);
        feeHelper.getPools(2, poolsNum + 1);

        vm.expectRevert(IPoolHelperCommon.IndexOutOfBounds.selector);
        feeHelper.getPools(poolsNum, poolsNum);
    }

    function testAddUnregisteredPool() public {
        address[] memory invalidAddresses = new address[](1);
        invalidAddresses[0] = address(0x1234);

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.PoolNotRegistered.selector, invalidAddresses[0]));

        feeHelper.addPools(invalidAddresses);
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

        feeHelper.addPools(pools);
    }
}
