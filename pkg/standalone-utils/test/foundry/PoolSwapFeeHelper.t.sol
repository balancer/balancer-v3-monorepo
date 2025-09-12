// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import { IPoolSwapFeeHelper } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IPoolSwapFeeHelper.sol";
import { IPoolHelperCommon } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IPoolHelperCommon.sol";
import { PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { PoolFactoryMock } from "@balancer-labs/v3-vault/contracts/test/PoolFactoryMock.sol";

import { PoolSwapFeeHelper } from "../../contracts/PoolSwapFeeHelper.sol";
import { BasePoolHelperTest } from "./utils/BasePoolHelperTest.sol";

contract PoolSwapFeeHelperTest is BasePoolHelperTest {
    uint256 constant NEW_SWAP_FEE_PERCENTAGE = 1.346e16;

    function setUp() public virtual override {
        BasePoolHelperTest.setUp();

        // admin is the helper contract owner; alice is the "partner" manager of the pool set.
        poolHelper = new PoolSwapFeeHelper(vault, admin);
        vm.prank(admin);
        alicePoolSetId = poolHelper.createPoolSet(alice);

        authorizer.grantRole(vault.getActionId(vault.setStaticSwapFeePercentage.selector), address(poolHelper));
    }

    function testAddPoolWithSwapManager() public {
        address[] memory pools = new address[](1);

        pools[0] = PoolFactoryMock(poolFactory).createPool("Test", "TEST");
        PoolRoleAccounts memory roleAccounts;
        roleAccounts.swapFeeManager = admin;

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
        vm.prank(admin);
        poolHelper.addPoolsToSet(alicePoolSetId, pools);
    }

    function testSetSwapFee() public {
        address[] memory pools = _addPools(10);

        for (uint256 i = 0; i < pools.length; ++i) {
            vm.prank(alice);
            PoolSwapFeeHelper(address(poolHelper)).setStaticSwapFeePercentage(pools[i], NEW_SWAP_FEE_PERCENTAGE);
        }

        for (uint256 i = 0; i < pools.length; i++) {
            uint256 swapFeePercentage = vault.getStaticSwapFeePercentage(pools[i]);

            assertEq(swapFeePercentage, NEW_SWAP_FEE_PERCENTAGE, "Wrong swap fee percentage");
        }
    }

    function testSetSwapFeeIfPoolIsNotInList() public {
        _addPools(10);

        vm.expectRevert(abi.encodeWithSelector(IPoolHelperCommon.PoolNotInSet.selector, address(0x00), alicePoolSetId));
        vm.prank(alice);
        PoolSwapFeeHelper(address(poolHelper)).setStaticSwapFeePercentage(address(0), NEW_SWAP_FEE_PERCENTAGE);
    }

    function testSetSwapFeeWithoutPermission() public {
        address[] memory pools = _addPools(1);

        vm.expectRevert(IPoolHelperCommon.SenderIsNotPoolSetManager.selector);
        PoolSwapFeeHelper(address(poolHelper)).setStaticSwapFeePercentage(pools[0], NEW_SWAP_FEE_PERCENTAGE);
    }
}
