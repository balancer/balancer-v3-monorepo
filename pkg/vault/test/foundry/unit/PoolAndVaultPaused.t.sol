// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { VaultState } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { BaseVaultTest } from "../utils/BaseVaultTest.sol";

contract PoolAndVaultPausedTest is BaseVaultTest {
    // A number that is much smaller than the vault pause buffer end time, so we can play with
    // pool and vault pause windows.
    uint32 private constant _FIXED_POOL_PAUSE_END_TIME = 1e5;
    uint256 private _vaultBufferPeriodEndTimeTest;

    function setUp() public virtual override {
        BaseVaultTest.setUp();
        vault.manualSetPoolPauseWindowEndTime(pool, _FIXED_POOL_PAUSE_END_TIME);

        _vaultBufferPeriodEndTimeTest = vault.getBufferPeriodEndTime();
    }

    /*******************************************************************************
                                _ensurePoolNotPaused
    *******************************************************************************/

    function testPausedPoolBeforeBufferPeriod() public {
        // Sets the time before the pause buffer period.
        vm.warp(_FIXED_POOL_PAUSE_END_TIME - 1);

        vault.manualSetPoolPaused(pool, true);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.PoolPaused.selector, pool));
        vault.ensurePoolNotPaused(pool);
    }

    function testPausedPoolAfterBufferPeriod() public {
        // Sets the time after the pause buffer period.
        vm.warp(_getTimeAfterPoolPauseBufferPeriod());

        vault.manualSetPoolPaused(pool, true);
        // If function does not revert, test passes.
        vault.ensurePoolNotPaused(pool);
    }

    function testUnpausedPoolBeforeBufferPeriod() public {
        // Sets the time before the pause buffer period.
        vm.warp(_FIXED_POOL_PAUSE_END_TIME - 1);

        vault.manualSetPoolPaused(pool, false);
        // If function does not revert, test passes.
        vault.ensurePoolNotPaused(pool);
    }

    function testUnpausedPoolAfterBufferPeriod() public {
        // Sets the time after the pause buffer period.
        vm.warp(_getTimeAfterPoolPauseBufferPeriod());

        vault.manualSetPoolPaused(pool, false);
        // If function does not revert, test passes.
        vault.ensurePoolNotPaused(pool);
    }

    /*******************************************************************************
                           _ensureUnpausedAndGetVaultState
    *******************************************************************************/

    function testVaultPausedByFlag() public {
        // Sets the time before the vault pause buffer period.
        vm.warp(_vaultBufferPeriodEndTimeTest - 1);
        vault.manualSetVaultPaused(true);

        vm.expectRevert(IVaultErrors.VaultPaused.selector);
        vault.ensureUnpausedAndGetVaultState(pool);
    }

    function testVaultPausedByFlagAfterBufferTime() public {
        // Sets the time before the vault pause buffer period.
        vm.warp(_vaultBufferPeriodEndTimeTest + 1);
        vault.manualSetVaultPaused(true);

        // Since the buffer period has passed, the function should not revert.
        vault.ensureUnpausedAndGetVaultState(pool);
    }

    function testVaultUnpausedButPoolPaused() public {
        // Sets the time before the pause buffer period.
        vm.warp(_FIXED_POOL_PAUSE_END_TIME - 1);

        vault.manualSetVaultPaused(false);
        vault.manualSetPoolPaused(pool, true);

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.PoolPaused.selector, pool));
        vault.ensureUnpausedAndGetVaultState(pool);
    }

    function testVaultUnpausedButPoolPausedByFlagAfterBufferTime() public {
        // Sets the time before the pause buffer period.
        vm.warp(_getTimeAfterPoolPauseBufferPeriod());

        vault.manualSetVaultPaused(false);
        vault.manualSetPoolPaused(pool, true);

        // Since the buffer period has passed, the function should not revert.
        vault.ensureUnpausedAndGetVaultState(pool);
    }

    function testVaultPausedButPoolUnpaused() public {
        // Sets the time after the pool pause buffer period, but before vault pause buffer period (so flag is checked).
        vm.warp(_getTimeAfterPoolPauseBufferPeriod());

        vault.manualSetVaultPaused(true);
        vault.manualSetPoolPaused(pool, false);

        vm.expectRevert(IVaultErrors.VaultPaused.selector);
        vault.ensureUnpausedAndGetVaultState(pool);
    }

    function testVaultAndPoolUnpaused() public {
        // Sets the time after the pause buffer period.
        vm.warp(_getTimeAfterPoolPauseBufferPeriod());

        vault.manualSetVaultState(false, true);
        vault.manualSetPoolPaused(pool, false);

        VaultState memory vaultState = vault.ensureUnpausedAndGetVaultState(pool);
        assertEq(vaultState.isVaultPaused, false, "vaultState.isVaultPaused should be false");
        assertEq(vaultState.isQueryDisabled, true, "vaultState.isQueryDisabled should be true");
    }

    // Returns the correct block.timestamp to consider the pool unpaused.
    function _getTimeAfterPoolPauseBufferPeriod() private view returns (uint256) {
        uint32 bufferPeriodDuration = vault.getBufferPeriodDuration();
        return _FIXED_POOL_PAUSE_END_TIME + bufferPeriodDuration + 1;
    }
}
