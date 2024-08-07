// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract RecoveryModeTest is BaseVaultTest {
    using ArrayHelpers for *;

    function setUp() public virtual override {
        BaseVaultTest.setUp();
    }

    function testRecoveryModeBalances() public {
        // Add initial liquidity.
        uint256[] memory amountsIn = [uint256(defaultAmount), uint256(defaultAmount)].toMemoryArray();

        vm.prank(alice);
        uint256 bptAmountOut = router.addLiquidityUnbalanced(pool, amountsIn, defaultAmount, false, bytes(""));

        // Raw and live should be in sync.
        assertRawAndLiveBalanceRelationship(true);

        // Put pool in recovery mode.
        vault.manualEnableRecoveryMode(pool);

        // Do a recovery withdrawal.
        vm.prank(alice);
        router.removeLiquidityRecovery(pool, bptAmountOut / 2);

        // Raw and live should be out of sync.
        assertRawAndLiveBalanceRelationship(false);

        vault.manualDisableRecoveryMode(pool);

        // Raw and live should be back in sync.
        assertRawAndLiveBalanceRelationship(true);
    }

    function assertRawAndLiveBalanceRelationship(bool shouldBeEqual) internal view {
        // Ensure raw and last live balances are in sync after the operation.
        uint256[] memory currentLiveBalances = vault.getCurrentLiveBalances(pool);
        uint256[] memory lastBalancesLiveScaled18 = vault.getLastLiveBalances(pool);

        assertEq(
            currentLiveBalances.length,
            lastBalancesLiveScaled18.length,
            "current/last live balance length mismatch"
        );

        for (uint256 i = 0; i < currentLiveBalances.length; ++i) {
            bool areEqual = currentLiveBalances[i] == lastBalancesLiveScaled18[i];

            shouldBeEqual ? assertTrue(areEqual) : assertFalse(areEqual);
        }
    }

    // Test permissionless Recovery Mode scenarios

    function testRecoveryModePermissionlessWhenVaultPaused() public {
        // When Vault is not paused, `enableRecoveryMode` is permissioned.
        require(vault.isVaultPaused() == false, "Vault should not be paused initially");

        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
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

        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        vm.prank(lp);
        vault.enableRecoveryMode(pool);

        // Pause Pool.
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

        uint32 bufferPeriodEndTime = vault.getBufferPeriodEndTime();

        // Ensure we are in the permissionless period of the Vault.
        skip(bufferPeriodEndTime);

        // Confirm the Vault is permissionless
        assertTrue(block.timestamp > bufferPeriodEndTime, "Time should be after the bufferPeriodEndTime");

        // Recovery Mode is permissioned even though the Vault's pause bit is set, because it's no longer pausable.
        assertFalse(vault.isVaultPaused(), "Vault should unpause itself after buffer expiration");
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        vm.prank(lp);
        vault.enableRecoveryMode(pool);

        // Can still set it if granted permission.
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

        // Ensure we are in the permissionless period of the Pool.
        (, , uint32 bufferPeriodEndTime, ) = vault.getPoolPausedState(pool);

        vm.warp(bufferPeriodEndTime + 1);

        // Confirm the Pool is permissionless.
        assertTrue(block.timestamp > bufferPeriodEndTime, "Time should be after Pool's buffer period end time");

        // Recovery Mode is permissioned even though the Pool's pause bit is set, because it's no longer pausable.
        assertFalse(vault.isPoolPaused(pool), "Pool should unpause itself after buffer expiration");
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        vm.prank(lp);
        vault.enableRecoveryMode(pool);

        // Can still set it if granted permission.
        authorizer.grantRole(vault.getActionId(IVaultAdmin.enableRecoveryMode.selector), admin);

        vm.prank(admin);
        vault.enableRecoveryMode(pool);

        assertTrue(vault.isPoolInRecoveryMode(pool), "Pool should be in Recovery Mode");
    }

    // Disable Recovery Mode

    function testDisableRecoveryModeRevert() public {
        assertFalse(vault.isPoolInRecoveryMode(pool), "Pool should not be in Recovery Mode");

        authorizer.grantRole(vault.getActionId(IVaultAdmin.disableRecoveryMode.selector), admin);
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.PoolNotInRecoveryMode.selector, pool));
        vault.disableRecoveryMode(pool);
    }

    function testDisableRecoveryModeSuccessfully() public {
        // Enable recovery mode
        authorizer.grantRole(vault.getActionId(IVaultAdmin.enableRecoveryMode.selector), admin);
        vm.prank(admin);
        vault.enableRecoveryMode(pool);

        assertTrue(vault.isPoolInRecoveryMode(pool), "Pool should be in Recovery Mode");

        authorizer.grantRole(vault.getActionId(IVaultAdmin.disableRecoveryMode.selector), admin);
        vm.prank(admin);
        vault.disableRecoveryMode(pool);

        assertFalse(vault.isPoolInRecoveryMode(pool), "Pool not should be in Recovery Mode");
    }
}
