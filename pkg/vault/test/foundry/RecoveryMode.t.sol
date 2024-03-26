// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";

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

        assertEq(currentLiveBalances.length, lastLiveBalances.length);

        for (uint256 i = 0; i < currentLiveBalances.length; i++) {
            bool areEqual = currentLiveBalances[i] == lastLiveBalances[i];

            shouldBeEqual ? assertTrue(areEqual) : assertFalse(areEqual);
        }
    }

    // Test permissionless Recovery Mode scenarios

    function testRecoveryModePermissionlessWhenVaultPaused() public {
        // When Vault is not paused, `enableRecoveryMode` is permissioned.
        assertFalse(vault.isVaultPaused());

        vm.expectRevert(abi.encodeWithSelector(IAuthentication.SenderNotAllowed.selector));
        vm.prank(lp);
        vault.enableRecoveryMode(pool);

        // Pause Vault
        vault.manualPauseVault();

        assertTrue(vault.isVaultPaused());
        assertFalse(vault.isPoolInRecoveryMode(pool));

        // Can enable recovery mode by an LP with no permission grant.
        vm.prank(lp);
        vault.enableRecoveryMode(pool);

        assertTrue(vault.isVaultPaused());
        assertTrue(vault.isPoolInRecoveryMode(pool));
    }

    function testRecoveryModePermissionlessWhenPoolPaused() public {
        // When Pool is not paused, `enableRecoveryMode` is permissioned.
        assertFalse(vault.isPoolPaused(pool));
        // Also ensure Vault is not paused.
        assertFalse(vault.isVaultPaused());

        vm.expectRevert(abi.encodeWithSelector(IAuthentication.SenderNotAllowed.selector));
        vm.prank(lp);
        vault.enableRecoveryMode(pool);

        // Pause Pool
        vault.manualSetPoolPaused(pool, true);

        assertTrue(vault.isPoolPaused(pool));
        assertFalse(vault.isPoolInRecoveryMode(pool));

        // Can enable recovery mode by an LP with no permission grant.
        vm.prank(lp);
        vault.enableRecoveryMode(pool);

        assertFalse(vault.isVaultPaused());
        assertTrue(vault.isPoolPaused(pool));
        assertTrue(vault.isPoolInRecoveryMode(pool));
    }

    function testRecoveryModePermissionedWhenVaultPermissionless() public {
        // Pause Vault
        vault.manualPauseVault();
        assertTrue(vault.isVaultPaused());
        assertFalse(vault.isPoolPaused(pool));

        // Enter the permissionless period of the Vault.
        skip(500 days);

        // Confirm the Vault is permissionless
        uint256 bufferPeriodEndTime = vault.getBufferPeriodEndTime();
        assertTrue(block.timestamp > bufferPeriodEndTime);

        // Recovery Mode is permissioned even though the Vault's pause bit is set, because it's no longer pausable.
        assertFalse(vault.isVaultPaused());
        vm.expectRevert(abi.encodeWithSelector(IAuthentication.SenderNotAllowed.selector));
        vm.prank(lp);
        vault.enableRecoveryMode(pool);

        // Can still set it if granted permission
        authorizer.grantRole(vault.getActionId(IVaultAdmin.enableRecoveryMode.selector), admin);

        vm.prank(admin);
        vault.enableRecoveryMode(pool);

        assertTrue(vault.isPoolInRecoveryMode(pool));
    }

    function testRecoveryModePermissionedWhenPoolPermissionless() public {
        // Also ensure Vault is not paused.
        assertFalse(vault.isVaultPaused());

        // Pause pool
        vault.manualSetPoolPaused(pool, true);

        assertTrue(vault.isPoolPaused(pool));
        assertFalse(vault.isPoolInRecoveryMode(pool));

        // Enter the permissionless period of the Pool.
        skip(500 days);

        // Confirm the Pool is permissionless
        (, , uint256 bufferPeriodEndTime, ) = vault.getPoolPausedState(pool);
        assertTrue(block.timestamp > bufferPeriodEndTime);

        // Recovery Mode is permissioned even though the Pool's pause bit is set, because it's no longer pausable.
        assertFalse(vault.isPoolPaused(pool));
        vm.expectRevert(abi.encodeWithSelector(IAuthentication.SenderNotAllowed.selector));
        vm.prank(lp);
        vault.enableRecoveryMode(pool);

        // Can still set it if granted permission
        authorizer.grantRole(vault.getActionId(IVaultAdmin.enableRecoveryMode.selector), admin);

        vm.prank(admin);
        vault.enableRecoveryMode(pool);

        assertTrue(vault.isPoolInRecoveryMode(pool));
    }
}
