// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import "@balancer-labs/v3-interfaces/contracts/test/IVaultMainMock.sol";

import { BaseVaultTest } from "../utils/BaseVaultTest.sol";

contract PoolAndVaultPausedTest is BaseVaultTest {
    // block.timestamp in which VaultMock sets the end of pool's pause buffer period
    uint256 private constant _FIXED_POOL_PAUSE_END_TIME = 2 ** 16;
    uint256 private _VAULT_BUFFER_END_TIME;

    function setUp() public virtual override {
        BaseVaultTest.setUp();
        _VAULT_BUFFER_END_TIME = IVaultAdmin(address(vault)).getBufferPeriodEndTime();
    }

    /*******************************************************************************
                                _ensurePoolNotPaused
    *******************************************************************************/

    function testPausedPoolBeforeBufferPeriod() public {
        // sets the time before the pause buffer period
        vm.warp(_FIXED_POOL_PAUSE_END_TIME);

        vault.manualSetPoolPaused(address(pool), true, _FIXED_POOL_PAUSE_END_TIME);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.PoolPaused.selector, address(pool)));
        vault.ensurePoolNotPaused(address(pool));
    }

    function testPausedPoolAfterBufferPeriod() public {
        // sets the time after the pause buffer period
        vm.warp(_getTimeAfterPoolPauseBufferPeriod());

        vault.manualSetPoolPaused(address(pool), true, _FIXED_POOL_PAUSE_END_TIME);
        // If function does not revert, test passes
        vault.ensurePoolNotPaused(address(pool));
    }

    function testUnpausedPoolBeforeBufferPeriod() public {
        // sets the time before the pause buffer period
        vm.warp(_FIXED_POOL_PAUSE_END_TIME);

        vault.manualSetPoolPaused(address(pool), false, _FIXED_POOL_PAUSE_END_TIME);
        // If function does not revert, test passes
        vault.ensurePoolNotPaused(address(pool));
    }

    function testUnpausedPoolAfterBufferPeriod() public {
        // sets the time after the pause buffer period
        vm.warp(_getTimeAfterPoolPauseBufferPeriod());

        vault.manualSetPoolPaused(address(pool), false, _FIXED_POOL_PAUSE_END_TIME);
        // If function does not revert, test passes
        vault.ensurePoolNotPaused(address(pool));
    }

    /*******************************************************************************
                           _ensureUnpausedAndGetVaultState
    *******************************************************************************/

    function testVaultPausedByFlag() public {
        // sets the time before the vault pause buffer period
        vm.warp(_VAULT_BUFFER_END_TIME - 1);
        vault.manualSetVaultPaused(true);

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.VaultPaused.selector));
        vault.ensureUnpausedAndGetVaultState(address(pool));
    }

    function testVaultPausedByFlagAfterBufferTime() public {
        // sets the time before the vault pause buffer period
        vm.warp(_VAULT_BUFFER_END_TIME + 1);
        vault.manualSetVaultPaused(true);

        // Since buffer time has passed, the function should not revert
        vault.ensureUnpausedAndGetVaultState(address(pool));
    }

    function testVaultUnpausedButPoolPaused() public {
        // sets the time before the pause buffer period
        vm.warp(_FIXED_POOL_PAUSE_END_TIME);

        vault.manualSetVaultPaused(false);
        vault.manualSetPoolPaused(address(pool), true, _FIXED_POOL_PAUSE_END_TIME);

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.PoolPaused.selector, address(pool)));
        vault.ensureUnpausedAndGetVaultState(address(pool));
    }

    function testVaultPausedButPoolUnpaused() public {
        // sets the time after the pool pause buffer period, but before vault pause buffer period (so flag is checked)
        vm.warp(_getTimeAfterPoolPauseBufferPeriod());

        vault.manualSetVaultPaused(true);
        vault.manualSetPoolPaused(address(pool), false, _FIXED_POOL_PAUSE_END_TIME);

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.VaultPaused.selector));
        vault.ensureUnpausedAndGetVaultState(address(pool));
    }

    function testVaultAndPoolUnpaused() public {
        // sets the time after the pause buffer period
        vm.warp(_getTimeAfterPoolPauseBufferPeriod());

        vault.manualSetVaultState(false, true, 3e16, 5e17);
        vault.manualSetPoolPaused(address(pool), false, _FIXED_POOL_PAUSE_END_TIME);

        VaultState memory vaultState = vault.ensureUnpausedAndGetVaultState(address(pool));
        assertEq(vaultState.isVaultPaused, false, "vaultState.isVaultPaused should be false");
        assertEq(vaultState.isQueryDisabled, true, "vaultState.isQueryDisabled should be true");
        assertEq(vaultState.protocolSwapFeePercentage, 3e16, "vaultState.protocolSwapFeePercentage should be 3e16");
        assertEq(vaultState.protocolYieldFeePercentage, 5e17, "vaultState.protocolYieldFeePercentage should be 5e17");
    }

    // Returns the correct block.timestamp to consider the pool unpaused
    // (cannot be used to check vault pause. For that, use the variable _VAULT_BUFFER_END_TIME)
    function _getTimeAfterPoolPauseBufferPeriod() private view returns (uint256) {
        uint256 bufferPeriodDuration = IVaultAdmin(address(vault)).getBufferPeriodDuration();
        return _FIXED_POOL_PAUSE_END_TIME + bufferPeriodDuration + 1;
    }
}
