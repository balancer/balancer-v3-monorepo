// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract VaultSwapWithRatesTest is BaseVaultTest {
    using CastingHelpers for address[];
    using ArrayHelpers for *;
    using FixedPoint for *;

    // Track the indices for the local dai/wsteth pool.
    uint256 internal daiIdx;
    uint256 internal wstethIdx;

    function setUp() public virtual override {
        BaseVaultTest.setUp();
    }

    function testWithNonPoolCall() public {
        // Only registered pools can emit aux event
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.PoolNotRegistered.selector, admin));
        vm.prank(admin);
        vault.emitAuxiliaryEvent("TestEvent", abi.encode(777));
    }

    function testEventEmitted() public {
        uint256 testValue = 777;

        vm.expectEmit();
        emit IVaultEvents.VaultAuxiliary(pool, "TestEvent", abi.encode(testValue));

        vm.prank(admin);
        PoolMock(pool).mockEventFunction(testValue);
    }
}
