// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { IPoolHelperCommon } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IPoolHelperCommon.sol";

import { ProtocolFeeHelper } from "../../contracts/ProtocolFeeHelper.sol";
import { BasePoolHelperTest } from "./utils/BasePoolHelperTest.sol";

contract PoolPauseHelperTest is BasePoolHelperTest {
    uint256 constant NEW_SWAP_FEE_PERCENTAGE = 1.346e16;
    uint256 constant NEW_YIELD_FEE_PERCENTAGE = 8.472e16;

    IAuthentication feeControllerAuth;

    function setUp() public virtual override {
        BasePoolHelperTest.setUp();

        // admin is the helper contract owner; alice is the "partner" manager of the pool set.
        poolHelper = new ProtocolFeeHelper(vault, admin);
        vm.prank(admin);
        alicePoolSetId = poolHelper.createPoolSet(alice);

        feeControllerAuth = IAuthentication(address(feeController));

        authorizer.grantRole(
            feeControllerAuth.getActionId(feeController.setProtocolSwapFeePercentage.selector),
            address(poolHelper)
        );
        authorizer.grantRole(
            feeControllerAuth.getActionId(feeController.setProtocolYieldFeePercentage.selector),
            address(poolHelper)
        );
    }

    function testSetProtocolFee() public {
        address[] memory pools = _addPools(10);

        vm.startPrank(alice);
        for (uint256 i = 0; i < pools.length; ++i) {
            ProtocolFeeHelper(address(poolHelper)).setProtocolSwapFeePercentage(pools[i], NEW_SWAP_FEE_PERCENTAGE);
            ProtocolFeeHelper(address(poolHelper)).setProtocolYieldFeePercentage(pools[i], NEW_YIELD_FEE_PERCENTAGE);
        }
        vm.stopPrank();

        for (uint256 i = 0; i < pools.length; i++) {
            (uint256 protocolSwapFeePercentage, ) = feeController.getPoolProtocolSwapFeeInfo(pools[i]);
            (uint256 protocolYieldFeePercentage, ) = feeController.getPoolProtocolYieldFeeInfo(pools[i]);

            assertEq(protocolSwapFeePercentage, NEW_SWAP_FEE_PERCENTAGE, "Wrong swap fee percentage");
            assertEq(protocolYieldFeePercentage, NEW_YIELD_FEE_PERCENTAGE, "Wrong yield fee percentage");
        }
    }

    function testSetProtocolFeeIfPoolIsNotInList() public {
        _addPools(10);

        vm.expectRevert(abi.encodeWithSelector(IPoolHelperCommon.PoolNotInSet.selector, address(0x00), alicePoolSetId));
        vm.prank(alice);
        ProtocolFeeHelper(address(poolHelper)).setProtocolSwapFeePercentage(address(0), NEW_SWAP_FEE_PERCENTAGE);
    }

    function testSetProtocolFeeWithoutPermission() public {
        address[] memory pools = _addPools(1);

        vm.expectRevert(IPoolHelperCommon.SenderIsNotPoolSetManager.selector);
        ProtocolFeeHelper(address(poolHelper)).setProtocolSwapFeePercentage(pools[0], NEW_SWAP_FEE_PERCENTAGE);
    }

    function testSetProtocolFeeWithoutFeeControllerPermission() public {
        address[] memory pools = _addPools(1);

        authorizer.revokeRole(
            feeControllerAuth.getActionId(feeController.setProtocolSwapFeePercentage.selector),
            address(poolHelper)
        );

        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        vm.prank(alice);
        ProtocolFeeHelper(address(poolHelper)).setProtocolSwapFeePercentage(pools[0], NEW_SWAP_FEE_PERCENTAGE);
    }
}
