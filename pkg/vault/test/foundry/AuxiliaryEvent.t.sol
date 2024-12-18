// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IVaultEvents } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultEvents.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";

import { PoolMock } from "../../contracts/test/PoolMock.sol";

import { BaseTestState, BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract AuxiliaryEventTest is BaseVaultTest {
    function setUp() public virtual override {
        BaseVaultTest.setUp();
    }

    function testWithNonPoolCall() public {
        BaseTestState bState = getBaseTestState();

        // Only registered pools can emit aux event
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.PoolNotRegistered.selector, bState.accounts.admin));

        vm.prank(bState.accounts.admin);
        vault.emitAuxiliaryEvent("TestEvent", abi.encode(777));
    }

    function testEventEmitted() public {
        uint256 testValue = 777;

        vm.expectEmit();
        emit IVaultEvents.VaultAuxiliary(pool, "TestEvent", abi.encode(testValue));

        PoolMock(pool).mockEventFunction(testValue);
    }
}
