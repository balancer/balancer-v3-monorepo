// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { IAuthorizer } from "@balancer-labs/v3-interfaces/contracts/vault/IAuthorizer.sol";
import { IProtocolFeeController } from "@balancer-labs/v3-interfaces/contracts/vault/IProtocolFeeController.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";

import {
    ReentrancyGuardTransient
} from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/ReentrancyGuardTransient.sol";

import { BaseVaultTest } from "../../utils/BaseVaultTest.sol";

contract VaultAdminMutationTest is BaseVaultTest {
    function setUp() public virtual override {
        BaseVaultTest.setUp();
    }

    function testIsVaultPausedWhenNotVault() public {
        vm.expectRevert(IVaultErrors.NotVaultDelegateCall.selector);
        vaultAdmin.isVaultPaused();
    }

    function testGetVaultPausedStateWhenNotVault() public {
        vm.expectRevert(IVaultErrors.NotVaultDelegateCall.selector);
        vaultAdmin.getVaultPausedState();
    }

    function testPauseVaultWhenNotVault() public {
        vm.expectRevert(IVaultErrors.NotVaultDelegateCall.selector);
        vaultAdmin.pauseVault();
    }

    function testPauseVaultWhenNotAuthenticated() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        vault.pauseVault();
    }

    function testPauseVaultSuccessfully() public {
        authorizer.grantRole(vault.getActionId(IVaultAdmin.pauseVault.selector), admin);
        vm.prank(admin);
        vault.pauseVault();
        assertTrue(vault.isVaultPaused(), "Vault is not paused");
    }

    function testUnpauseVaultWhenNotVault() public {
        vm.expectRevert(IVaultErrors.NotVaultDelegateCall.selector);
        vaultAdmin.unpauseVault();
    }

    function testUnpauseVaultWhenNotAuthenticated() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        vault.unpauseVault();
    }

    function testUnpauseVaultSuccessfully() public {
        authorizer.grantRole(vault.getActionId(IVaultAdmin.pauseVault.selector), admin);
        authorizer.grantRole(vault.getActionId(IVaultAdmin.unpauseVault.selector), admin);
        vm.startPrank(admin);
        vault.pauseVault();
        assertTrue(vault.isVaultPaused(), "Vault is not paused");

        vault.unpauseVault();
        assertFalse(vault.isVaultPaused(), "Vault is not unpaused");
        vm.stopPrank();
    }

    function testPausePoolWithoutRegisteredPool() public {
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.PoolNotRegistered.selector, address(0)));
        vault.pausePool(address(0));
    }

    function testPausePoolWhenNotVault() public {
        vm.expectRevert(IVaultErrors.NotVaultDelegateCall.selector);
        vaultAdmin.pausePool(pool);
    }

    function testPausePoolWhenNotAuthenticated() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        vault.pausePool(pool);
    }

    function testUnpausePoolWithoutRegisteredPool() public {
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.PoolNotRegistered.selector, address(0)));
        vault.unpausePool(address(0));
    }

    function testUnpausePoolWhenNotVault() public {
        vm.expectRevert(IVaultErrors.NotVaultDelegateCall.selector);
        vaultAdmin.unpausePool(pool);
    }

    function testUnpausePoolWhenNotAuthenticated() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        vault.unpausePool(pool);
    }

    function testSetStaticSwapFeePercentageWithoutRegisteredPool() public {
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.PoolNotRegistered.selector, address(0)));
        vault.setStaticSwapFeePercentage(address(0), 1);
    }

    function testSetStaticSwapFeePercentageWhenNotVault() public {
        vm.expectRevert(IVaultErrors.NotVaultDelegateCall.selector);
        vaultAdmin.setStaticSwapFeePercentage(pool, 1);
    }

    function testSetStaticSwapFeePercentageWhenNotAuthenticated() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        vault.setStaticSwapFeePercentage(pool, 1);
    }

    function testSetStaticSwapFeePercentageWhenPoolPaused() public {
        vault.manualPausePool(pool);
        authorizer.grantRole(vault.getActionId(IVaultAdmin.setStaticSwapFeePercentage.selector), admin);
        vm.prank(admin);

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.PoolPaused.selector, pool));
        vault.setStaticSwapFeePercentage(pool, 1);
    }

    function testSetStaticSwapFeePercentageWhenVaultPaused() public {
        vault.manualPauseVault();
        authorizer.grantRole(vault.getActionId(IVaultAdmin.setStaticSwapFeePercentage.selector), admin);
        vm.prank(admin);

        vm.expectRevert(IVaultErrors.VaultPaused.selector);
        vault.setStaticSwapFeePercentage(pool, 1);
    }

    function testCollectAggregateFeesWhenNotVault() public {
        vm.expectRevert(IVaultErrors.NotVaultDelegateCall.selector);
        vaultAdmin.collectAggregateFees(pool);
    }

    function testCollectAggregateFeesWithoutRegisteredPool() public {
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.PoolNotRegistered.selector, address(0)));
        vault.collectAggregateFees(address(0));
    }

    function testUpdateAggregateSwapFeesWhenNotVault() public {
        vm.expectRevert(IVaultErrors.NotVaultDelegateCall.selector);
        vaultAdmin.updateAggregateSwapFeePercentage(pool, 1);
    }

    function testUpdateAggregateSwapFeesWhenNotProtocolFeeController() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        vault.updateAggregateSwapFeePercentage(pool, 1);
    }

    function testUpdateAggregateYieldFeesWhenNotVault() public {
        vm.expectRevert(IVaultErrors.NotVaultDelegateCall.selector);
        vaultAdmin.updateAggregateYieldFeePercentage(pool, 1);
    }

    function testUpdateAggregateYieldFeesWhenNotProtocolFeeController() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        vault.updateAggregateYieldFeePercentage(pool, 1);
    }

    function testSetProtocolFeeControllerWhenNotVault() public {
        vm.expectRevert(IVaultErrors.NotVaultDelegateCall.selector);
        vaultAdmin.setProtocolFeeController(IProtocolFeeController(address(1)));
    }

    function testSetProtocolFeeControllerWhenNotAuthenticated() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        vault.setProtocolFeeController(IProtocolFeeController(address(1)));
    }

    function testSetProtocolFeeControllerSuccessfully() public {
        IProtocolFeeController newProtocolFeeController = IProtocolFeeController(address(0x123));

        authorizer.grantRole(vault.getActionId(IVaultAdmin.setProtocolFeeController.selector), admin);
        vm.prank(admin);
        vault.setProtocolFeeController(newProtocolFeeController);

        assertEq(
            address(vault.getProtocolFeeController()),
            address(newProtocolFeeController),
            "ProtocolFeeController is wrong"
        );
    }

    function testEnableRecoveryModeWithoutRegisteredPool() public {
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.PoolNotRegistered.selector, address(0)));
        vault.enableRecoveryMode(address(0));
    }

    function testEnableRecoveryModeWhenNotVault() public {
        vm.expectRevert(IVaultErrors.NotVaultDelegateCall.selector);
        vaultAdmin.enableRecoveryMode(pool);
    }

    function testDisableRecoveryModeWithoutRegisteredPool() public {
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.PoolNotRegistered.selector, address(0)));
        vault.disableRecoveryMode(address(0));
    }

    function testDisableRecoveryModeWhenNotVault() public {
        vm.expectRevert(IVaultErrors.NotVaultDelegateCall.selector);
        vaultAdmin.disableRecoveryMode(pool);
    }

    function testDisableRecoveryModeWhenNotAuthenticated() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        vault.disableRecoveryMode(pool);
    }

    function testDisableQueryWhenNotAuthenticated() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        vault.disableQuery();
    }

    function testDisableQueryWhenNotVault() public {
        vm.expectRevert(IVaultErrors.NotVaultDelegateCall.selector);
        vaultAdmin.disableQuery();
    }

    function testUnpauseVaultBuffersWhenNotAuthenticated() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        vault.unpauseVaultBuffers();
    }

    function testUnpauseVaultBuffersWhenNotVault() public {
        vm.expectRevert(IVaultErrors.NotVaultDelegateCall.selector);
        vaultAdmin.unpauseVaultBuffers();
    }

    function testPauseVaultBuffersWhenNotAuthenticated() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        vault.pauseVaultBuffers();
    }

    function testPauseVaultBuffersWhenNotVault() public {
        vm.expectRevert(IVaultErrors.NotVaultDelegateCall.selector);
        vaultAdmin.pauseVaultBuffers();
    }

    function testAddLiquidityToBufferWhenNotVault() public {
        vm.expectRevert(IVaultErrors.NotVaultDelegateCall.selector);
        vaultAdmin.addLiquidityToBuffer(IERC4626(address(0)), 0, 0, address(0));
    }

    function testAddLiquidityToBufferWhenNotUnlocked() public {
        vm.expectRevert(IVaultErrors.VaultIsNotUnlocked.selector);
        vault.addLiquidityToBuffer(IERC4626(address(0)), 0, 0, address(0));
    }

    function testAddLiquidityToBufferWhenPaused() public {
        vault.manualSetIsUnlocked(true);
        authorizer.grantRole(vault.getActionId(IVaultAdmin.pauseVaultBuffers.selector), admin);
        vm.prank(admin);
        vault.pauseVaultBuffers();

        vm.expectRevert(IVaultErrors.VaultBuffersArePaused.selector);
        vault.addLiquidityToBuffer(IERC4626(address(0)), 0, 0, address(0));
    }

    function testAddLiquidityToBufferNonReentrant() public {
        vault.manualSetIsUnlocked(true);
        vm.expectRevert(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector);
        vault.manualReentrancyAddLiquidityToBuffer(IERC4626(address(0)), 0, 0, address(0));
    }

    function testRemoveLiquidityFromBufferWhenNotVault() public {
        vm.expectRevert(IVaultErrors.NotVaultDelegateCall.selector);
        vaultAdmin.removeLiquidityFromBuffer(IERC4626(address(0)), 0, address(0));
    }

    function testRemoveLiquidityFromBufferWhenNotUnlocked() public {
        vm.expectRevert(IVaultErrors.VaultIsNotUnlocked.selector);
        vault.removeLiquidityFromBuffer(IERC4626(address(0)), 0, address(0));
    }

    function testRemoveLiquidityFromBufferWhenNonAuthenticated() public {
        vault.manualSetIsUnlocked(true);
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        vault.removeLiquidityFromBuffer(IERC4626(address(0)), 0, address(0));
    }

    function testRemoveLiquidityFromBufferNonReentrant() public {
        vault.manualSetIsUnlocked(true);
        authorizer.grantRole(vault.getActionId(IVaultAdmin.removeLiquidityFromBuffer.selector), address(vault));

        vm.expectRevert(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector);
        vault.manualReentrancyRemoveLiquidityFromBuffer(IERC4626(address(0)), 0, address(0));
    }

    function testGetBufferOwnerSharesWhenNotVault() public {
        vm.expectRevert(IVaultErrors.NotVaultDelegateCall.selector);
        vaultAdmin.getBufferOwnerShares(IERC4626(address(dai)), alice);
    }

    function testGetBufferTotalSharesWhenNotVault() public {
        vm.expectRevert(IVaultErrors.NotVaultDelegateCall.selector);
        vaultAdmin.getBufferTotalShares(IERC4626(address(dai)));
    }

    function testGetBufferBalanceWhenNotVault() public {
        vm.expectRevert(IVaultErrors.NotVaultDelegateCall.selector);
        vaultAdmin.getBufferBalance(IERC4626(address(dai)));
    }

    function testSetAuthorizerWhenNotAuthenticated() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        vault.setAuthorizer(_authorizer);
    }

    function testSetAuthorizerWhenNotVault() public {
        vm.expectRevert(IVaultErrors.NotVaultDelegateCall.selector);
        vaultAdmin.setAuthorizer(_authorizer);
    }

    function testSetAuthorizer() public {
        IAuthorizer newAuthorizer = IAuthorizer(address(0x123));

        authorizer.grantRole(vault.getActionId(IVaultAdmin.setAuthorizer.selector), admin);
        vm.prank(admin);
        vault.setAuthorizer(newAuthorizer);

        assertEq(address(vault.getAuthorizer()), address(newAuthorizer), "Authorizer is wrong");
    }
}
