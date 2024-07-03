// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { BaseVaultTest } from "../utils/BaseVaultTest.sol";

contract VaultAdminUnitTest is BaseVaultTest {
    function setUp() public virtual override {
        BaseVaultTest.setUp();

        // Authorize admin to pause and unpause vault
        authorizer.grantRole(vault.getActionId(IVaultAdmin.pauseVault.selector), admin);
        authorizer.grantRole(vault.getActionId(IVaultAdmin.unpauseVault.selector), admin);
    }

    // withValidPercentage
    function testWithValidPercentage() public view {
        // Any percentage below 100% is valid. This test expects not to be reverted.
        vault.mockWithValidPercentage(0.5e18);
    }

    function testWithValidPercentageRevert() public {
        // Any percentage above 100% is not valid and modifier should revert.
        vm.expectRevert(IVaultErrors.ProtocolFeesExceedTotalCollected.selector);
        vault.mockWithValidPercentage(1.5e18);
    }

    // _setVaultPaused
    function testPauseVaultWhenVaultIsPaused() public {
        // Pause vault
        vm.prank(admin);
        vault.pauseVault();
        assertTrue(vault.isVaultPaused(), "Vault is not paused");

        // Vault is already paused and we're trying to pause again.
        vm.expectRevert(IVaultErrors.VaultPaused.selector);
        vault.manualPauseVault();
    }

    function testUnpauseVaultWhenVaultIsUnpaused() public {
        assertFalse(vault.isVaultPaused(), "Vault is paused");

        // Vault is already unpaused and we're trying to unpause again.
        vm.expectRevert(IVaultErrors.VaultNotPaused.selector);
        vault.manualUnpauseVault();
    }

    function testPauseWithExpiredWindow() public {
        uint32 pauseTime = vault.getPauseWindowEndTime();
        assertFalse(vault.isVaultPaused(), "Vault is paused");

        // Changes block.timestamp to something greater than _pauseWindowEndTime
        vm.warp(pauseTime + 10);

        // Vault is not paused and we're trying to pause it, but the pause window has expired.
        vm.expectRevert(IVaultErrors.VaultPauseWindowExpired.selector);
        vault.manualPauseVault();
    }

    // _setPoolPaused
    function testPausePoolWhenPoolIsPaused() public {
        // Only internal functions are used, so the pool does not need to be registered.
        address pool = address(0x123);

        // Pause pool
        PoolConfig memory poolConfig;
        poolConfig.isPoolPaused = true;
        // Pause window cannot be expired
        poolConfig.pauseWindowEndTime = uint32(block.timestamp + 10);
        vault.manualSetPoolConfig(pool, poolConfig);

        // Pool is already paused and we're trying to pause again.
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.PoolPaused.selector, pool));
        vault.manualPausePool(pool);
    }

    function testUnpausePoolWhenPoolIsUnpaused() public {
        // Only internal functions are used, so the pool does not need to be registered.
        address pool = address(0x123);

        // Pool is already unpaused and we're trying to unpause again.
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.PoolNotPaused.selector, pool));
        vault.manualUnpausePool(pool);
    }

    // _ensurePoolNotInRecoveryMode
    function testEnsurePoolNotInRecoveryMode() public {
        // Only internal functions are used, so the pool does not need to be registered.
        address pool = address(0x123);

        // Should not revert because pool is not in recovery mode
        vault.mockEnsurePoolNotInRecoveryMode(pool);
    }

    function testEnsurePoolNotInRecoveryModeRevert() public {
        // Only internal functions are used, so the pool does not need to be registered.
        address pool = address(0x123);

        // Set recovery mode flag
        PoolConfig memory poolConfig;
        poolConfig.isPoolInRecoveryMode = true;
        vault.manualSetPoolConfig(pool, poolConfig);

        // Should not revert because pool is not in recovery mode
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.PoolInRecoveryMode.selector, pool));
        vault.mockEnsurePoolNotInRecoveryMode(pool);
    }
}
