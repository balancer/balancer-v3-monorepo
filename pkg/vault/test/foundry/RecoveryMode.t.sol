// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { PoolConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract RecoveryModeTest is BaseVaultTest {
    using ArrayHelpers for *;

    function setUp() public virtual override {
        BaseVaultTest.setUp();
    }

    function testRecoveryModeBalances() public {
        // Add initial liquidity
        uint256[] memory amountsIn = [uint256(defaultAmount), uint256(defaultAmount)].toMemoryArray();

        vm.prank(alice);
        uint256 bptAmountOut = router.addLiquidityUnbalanced(address(pool), amountsIn, defaultAmount, false, bytes(""));

        // Raw and live should be in sync
        assertRawAndLiveBalanceRelationship(true);

        // Put pool in recovery mode
        vault.manualEnableRecoveryMode(address(pool));

        // Do a recovery withdrawal
        vm.prank(alice);
        router.removeLiquidityRecovery(address(pool), bptAmountOut / 2);

        // Raw and live should be out of sync
        assertRawAndLiveBalanceRelationship(false);

        vault.manualDisableRecoveryMode(address(pool));

        // Raw and live should be back in sync
        assertRawAndLiveBalanceRelationship(true);
    }

    function assertRawAndLiveBalanceRelationship(bool shouldBeEqual) internal {
        // Ensure raw and last live balances are in sync after the operation
        uint256[] memory currentLiveBalances = vault.getCurrentLiveBalances(pool);
        uint256[] memory lastLiveBalances = vault.getLastLiveBalances(pool);

        assertEq(currentLiveBalances.length, lastLiveBalances.length, "current/last live balance length mismatch");

        for (uint256 i = 0; i < currentLiveBalances.length; i++) {
            bool areEqual = currentLiveBalances[i] == lastLiveBalances[i];

            shouldBeEqual ? assertTrue(areEqual) : assertFalse(areEqual);
        }
    }

    // Test recovery window

    function testRecoveryWindow() public {
        // When Pool is not paused, `enableRecoveryMode` is permissioned.
        require(vault.isPoolInRecoveryMode(pool) == false, "Pool should not be in recovery mode initially");

        authorizer.grantRole(vault.getActionId(IVaultAdmin.enableRecoveryMode.selector), admin);
        authorizer.grantRole(vault.getActionId(IVaultAdmin.disableRecoveryMode.selector), admin);

        vm.prank(admin);
        vault.enableRecoveryMode(pool);

        PoolConfig memory config = vault.getPoolConfig(address(pool));
        uint256 firstEndTime = block.timestamp + RECOVERY_WINDOW_DURATION;

        assertEq(config.recoveryWindowEndTime, firstEndTime, "Wrong initial recovery window end time");

        assertTrue(vault.isPoolInRecoveryMode(pool), "Pool not in recovery mode");

        // cannot disable it immediately
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.RecoveryWindowNotExpired.selector, pool));
        vault.disableRecoveryMode(pool);

        // Should be able to disable after the window expires
        skip(RECOVERY_WINDOW_DURATION + 1);

        vm.prank(admin);
        vault.disableRecoveryMode(pool);
        assertFalse(vault.isPoolInRecoveryMode(pool), "Pool still in recovery mode");

        // Can re-enable recovery mode, and it updates the end time.
        vm.prank(admin);
        vault.enableRecoveryMode(pool);

        config = vault.getPoolConfig(address(pool));
        uint256 secondEndTime = block.timestamp + RECOVERY_WINDOW_DURATION;

        assertTrue(secondEndTime > firstEndTime, "Recovery window end times inconsistent");

        assertEq(config.recoveryWindowEndTime, secondEndTime, "Wrong second recovery window end time");
    }

    // Test permissionless Recovery Mode scenarios

    function testRecoveryModePermissionlessWhenVaultPaused() public {
        // When Vault is not paused, `enableRecoveryMode` is permissioned.
        require(vault.isVaultPaused() == false, "Vault should not be paused initially");

        vm.expectRevert(abi.encodeWithSelector(IAuthentication.SenderNotAllowed.selector));
        vm.prank(lp);
        vault.enableRecoveryMode(pool);

        // Pause Vault
        vault.manualPauseVault();

        assertTrue(vault.isVaultPaused(), "Vault should be paused");
        assertFalse(vault.isPoolInRecoveryMode(pool), "Pool should not be in Recovery Mode after pausing");

        // Can enable recovery mode by an LP with no permission grant.
        vm.prank(lp);
        vault.enableRecoveryMode(pool);

        assertTrue(vault.isVaultPaused(), "Vault should still be paused");
        assertTrue(vault.isPoolInRecoveryMode(pool), "Pool should be in Recovery Mode");
    }

    function testRecoveryModePermissionlessWhenPoolPaused() public {
        // When Pool is not paused, `enableRecoveryMode` is permissioned.
        require(vault.isPoolPaused(pool) == false, "Pool should not be paused initially");
        // Also ensure Vault is not paused.
        require(vault.isVaultPaused() == false, "Vault should not be paused initially");

        vm.expectRevert(abi.encodeWithSelector(IAuthentication.SenderNotAllowed.selector));
        vm.prank(lp);
        vault.enableRecoveryMode(pool);

        // Pause Pool
        vault.manualSetPoolPaused(pool, true);

        assertTrue(vault.isPoolPaused(pool), "Pool should be paused");
        assertFalse(vault.isPoolInRecoveryMode(pool), "Pool should not be in Recovery Mode after pausing");

        // Can enable recovery mode by an LP with no permission grant.
        vm.prank(lp);
        vault.enableRecoveryMode(pool);

        assertFalse(vault.isVaultPaused(), "Vault should still not be paused");
        assertTrue(vault.isPoolPaused(pool), "Pool should still be paused");
        assertTrue(vault.isPoolInRecoveryMode(pool), "Pool should be in Recovery Mode");
    }

    function testRecoveryModePermissionedWhenVaultPermissionless() public {
        // Pause Vault
        vault.manualPauseVault();
        require(vault.isVaultPaused(), "Vault should be paused initially");
        require(vault.isPoolPaused(pool) == false, "Pool should not be paused initially");

        // Enter the permissionless period of the Vault.
        skip(500 days);

        // Confirm the Vault is permissionless
        uint256 bufferPeriodEndTime = vault.getBufferPeriodEndTime();
        assertTrue(block.timestamp > bufferPeriodEndTime, "Time should be after the bufferPeriodEndTime");

        // Recovery Mode is permissioned even though the Vault's pause bit is set, because it's no longer pausable.
        assertFalse(vault.isVaultPaused(), "Vault should unpause itself after buffer expiration");
        vm.expectRevert(abi.encodeWithSelector(IAuthentication.SenderNotAllowed.selector));
        vm.prank(lp);
        vault.enableRecoveryMode(pool);

        // Can still set it if granted permission
        authorizer.grantRole(vault.getActionId(IVaultAdmin.enableRecoveryMode.selector), admin);

        vm.prank(admin);
        vault.enableRecoveryMode(pool);

        assertTrue(vault.isPoolInRecoveryMode(pool), "Pool should be in Recovery Mode");
    }

    function testRecoveryModePermissionedWhenPoolPermissionless() public {
        // Also ensure Vault is not paused.
        require(vault.isVaultPaused() == false, "Vault should not be paused initially");

        // Pause pool
        vault.manualSetPoolPaused(pool, true);

        assertTrue(vault.isPoolPaused(pool), "Pool should be paused");
        assertFalse(vault.isPoolInRecoveryMode(pool), "Pool should not be in Recovery Mode after pausing");

        // Enter the permissionless period of the Pool.
        skip(500 days);

        // Confirm the Pool is permissionless
        (, , uint256 bufferPeriodEndTime, ) = vault.getPoolPausedState(pool);
        assertTrue(block.timestamp > bufferPeriodEndTime, "Time should be after Pool's buffer period end time");

        // Recovery Mode is permissioned even though the Pool's pause bit is set, because it's no longer pausable.
        assertFalse(vault.isPoolPaused(pool), "Pool should unpause itself after buffer expiration");
        vm.expectRevert(abi.encodeWithSelector(IAuthentication.SenderNotAllowed.selector));
        vm.prank(lp);
        vault.enableRecoveryMode(pool);

        // Can still set it if granted permission
        authorizer.grantRole(vault.getActionId(IVaultAdmin.enableRecoveryMode.selector), admin);

        vm.prank(admin);
        vault.enableRecoveryMode(pool);

        assertTrue(vault.isPoolInRecoveryMode(pool), "Pool should be in Recovery Mode");
    }
}
