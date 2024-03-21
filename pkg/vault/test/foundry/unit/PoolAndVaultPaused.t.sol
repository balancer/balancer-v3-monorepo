// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import "@balancer-labs/v3-interfaces/contracts/test/IVaultMainMock.sol";

import { BaseVaultTest } from "../utils/BaseVaultTest.sol";

contract PoolAndVaultPausedTest is BaseVaultTest {
    // block.timestamp in which VaultMock sets the end of pool's pause buffer period
    uint256 private constant _FIXED_PAUSE_END_TIME = 2 ** 16;

    function setUp() public virtual override {
        BaseVaultTest.setUp();
    }

    /*******************************************************************************
                                _ensurePoolNotPaused
    *******************************************************************************/

    function testPausedPoolBeforeBufferPeriod() public {
        // sets the time before the pause buffer period
        vm.warp(_FIXED_PAUSE_END_TIME);

        vault.manualSetPoolPaused(address(pool), true, _FIXED_PAUSE_END_TIME);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.PoolPaused.selector, address(pool)));
        vault.ensurePoolNotPaused(address(pool));
    }

    function testPausedPoolAfterBufferPeriod() public {
        // sets the time after the pause buffer period
        vm.warp(_getTimeAfterPauseBufferPeriod());

        vault.manualSetPoolPaused(address(pool), true, _FIXED_PAUSE_END_TIME);
        // If function does not revert, test passes
        vault.ensurePoolNotPaused(address(pool));
    }

    function testUnpausedPoolBeforeBufferPeriod() public {
        // sets the time before the pause buffer period
        vm.warp(_FIXED_PAUSE_END_TIME);

        vault.manualSetPoolPaused(address(pool), false, _FIXED_PAUSE_END_TIME);
        // If function does not revert, test passes
        vault.ensurePoolNotPaused(address(pool));
    }

    function testUnpausedPoolAfterBufferPeriod() public {
        // sets the time after the pause buffer period
        vm.warp(_getTimeAfterPauseBufferPeriod());

        vault.manualSetPoolPaused(address(pool), false, _FIXED_PAUSE_END_TIME);
        // If function does not revert, test passes
        vault.ensurePoolNotPaused(address(pool));
    }

    /*******************************************************************************
                           _ensureUnpausedAndGetVaultState
    *******************************************************************************/

    function testVaultPaused() public {
        vault.manualSetVaultPaused(true);

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.VaultPaused.selector));
        vault.ensureUnpausedAndGetVaultState(address(pool));
    }

    function testVaultUnpausedButPoolPaused() public {
        // sets the time before the pause buffer period
        vm.warp(_FIXED_PAUSE_END_TIME);

        vault.manualSetVaultPaused(false);
        vault.manualSetPoolPaused(address(pool), true, _FIXED_PAUSE_END_TIME);

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.PoolPaused.selector, address(pool)));
        vault.ensureUnpausedAndGetVaultState(address(pool));
    }

    function testVaultPausedButPoolUnpaused() public {
        // sets the time after the pause buffer period
        vm.warp(_getTimeAfterPauseBufferPeriod());

        vault.manualSetVaultPaused(true);
        vault.manualSetPoolPaused(address(pool), false, _FIXED_PAUSE_END_TIME);

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.VaultPaused.selector));
        vault.ensureUnpausedAndGetVaultState(address(pool));
    }

    function testVaultAndPoolUnpaused() public {
        // sets the time after the pause buffer period
        vm.warp(_getTimeAfterPauseBufferPeriod());

        vault.manualSetVaultState(false, true, 3e16, 5e17);
        vault.manualSetPoolPaused(address(pool), false, _FIXED_PAUSE_END_TIME);

        VaultState memory vaultState = vault.ensureUnpausedAndGetVaultState(address(pool));
        assertEq(vaultState.isVaultPaused, false, "vaultState.isVaultPaused should be false");
        assertEq(vaultState.isQueryDisabled, true, "vaultState.isQueryDisabled should be true");
        assertEq(vaultState.protocolSwapFeePercentage, 3e16, "vaultState.protocolSwapFeePercentage should be 3e16");
        assertEq(vaultState.protocolYieldFeePercentage, 5e17, "vaultState.protocolYieldFeePercentage should be 5e17");
    }

    // Returns the correct block.timestamp to consider the pool unpaused
    function _getTimeAfterPauseBufferPeriod() private view returns (uint256) {
        uint256 bufferPeriodDuration = IVaultAdmin(address(vault)).getBufferPeriodDuration();
        return _FIXED_PAUSE_END_TIME + bufferPeriodDuration + 1;
    }
}
