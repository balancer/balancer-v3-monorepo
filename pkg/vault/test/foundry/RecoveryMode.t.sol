// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IVaultEvents } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultEvents.sol";
import { IPoolInfo } from "@balancer-labs/v3-interfaces/contracts/pool-utils/IPoolInfo.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";
import { BalancerPoolToken } from "../../contracts/BalancerPoolToken.sol";

contract RecoveryModeTest is BaseVaultTest {
    using FixedPoint for uint256;
    using ArrayHelpers for *;

    function setUp() public virtual override {
        BaseVaultTest.setUp();
    }

    function testRecoveryModeEmitsPoolBalanceChangedEvent() public {
        // Add initial liquidity.
        uint256[] memory amountsIn = [uint256(defaultAmount), uint256(defaultAmount)].toMemoryArray();

        vm.prank(alice);
        (, uint256 bptAmountOut, ) = router.addLiquidityCustom(pool, amountsIn, bptAmount, false, bytes(""));

        // Put pool in recovery mode.
        vault.manualEnableRecoveryMode(pool);

        // Avoid roundtrip fee.
        vault.manualSetAddLiquidityCalledFlag(pool, false);
        assertFalse(vault.getAddLiquidityCalledFlag(pool), "Transient AddLiquidity flag set");

        uint256 initialSupply = IERC20(pool).totalSupply();
        uint256 amountToRemove = bptAmountOut / 2;

        vm.expectEmit();
        emit IVaultEvents.PoolBalanceChanged(
            pool,
            alice,
            initialSupply - amountToRemove, // totalSupply after the operation
            [-int256(defaultAmount) / 2, -int256(defaultAmount) / 2].toMemoryArray(),
            new uint256[](2)
        );

        uint256 daiBalanceBefore = dai.balanceOf(alice);
        uint256 usdcBalanceBefore = usdc.balanceOf(alice);

        (, , uint256[] memory poolBalancesBefore, ) = IPoolInfo(pool).getTokenInfo();

        // Do a recovery withdrawal.
        vm.prank(alice);
        router.removeLiquidityRecovery(pool, amountToRemove);

        uint256 bptAfter = IERC20(pool).balanceOf(alice);
        assertEq(bptAfter, amountToRemove); // this is half the BPT
        assertEq(initialSupply - IERC20(pool).totalSupply(), amountToRemove);

        uint256 daiBalanceAfter = dai.balanceOf(alice);
        uint256 usdcBalanceAfter = usdc.balanceOf(alice);

        assertEq(daiBalanceAfter - daiBalanceBefore, defaultAmount / 2, "Ending DAI balance wrong (alice)");
        assertEq(usdcBalanceAfter - usdcBalanceBefore, defaultAmount / 2, "Ending USDC balance wrong (alice)");

        (, , uint256[] memory poolBalancesAfter, ) = IPoolInfo(pool).getTokenInfo();
        assertEq(poolBalancesBefore[0] - poolBalancesAfter[0], defaultAmount / 2, "Ending balance[0] wrong (pool)");
        assertEq(poolBalancesBefore[1] - poolBalancesAfter[1], defaultAmount / 2, "Ending balance[1] wrong (pool)");
    }

    function testRecoveryModeWithRoundtripFee() public {
        // Add initial liquidity.
        uint256[] memory amountsIn = [uint256(defaultAmount), uint256(defaultAmount)].toMemoryArray();

        vm.prank(alice);
        (, uint256 bptAmountOut, ) = router.addLiquidityCustom(pool, amountsIn, bptAmount, false, bytes(""));

        // Put pool in recovery mode.
        vault.manualEnableRecoveryMode(pool);
        // Set the fee, and flag to trigger collection of it.
        vault.manualSetStaticSwapFeePercentage(pool, BASE_MAX_SWAP_FEE);
        // Will still be set from the add operation above.
        assertTrue(vault.getAddLiquidityCalledFlag(pool), "Transient AddLiquidity flag not set");

        uint256 initialSupply = IERC20(pool).totalSupply();
        uint256 amountToRemove = bptAmountOut / 2;
        uint256 amountOutWithoutFee = defaultAmount / 2;
        uint256 feeAmount = amountOutWithoutFee.mulDown(BASE_MAX_SWAP_FEE);
        uint256 amountOutAfterFee = amountOutWithoutFee - feeAmount;

        vm.expectEmit();
        emit IVaultEvents.PoolBalanceChanged(
            pool,
            alice,
            initialSupply - amountToRemove, // totalSupply after the operation
            [-int256(amountOutAfterFee), -int256(amountOutAfterFee)].toMemoryArray(),
            [feeAmount, feeAmount].toMemoryArray()
        );

        uint256 daiBalanceBefore = dai.balanceOf(alice);
        uint256 usdcBalanceBefore = usdc.balanceOf(alice);

        (, , uint256[] memory poolBalancesBefore, ) = IPoolInfo(pool).getTokenInfo();

        // Do a recovery withdrawal.
        vm.prank(alice);
        router.removeLiquidityRecovery(pool, amountToRemove);

        uint256 bptAfter = IERC20(pool).balanceOf(alice);
        assertEq(bptAfter, amountToRemove); // this is half the BPT
        assertEq(initialSupply - IERC20(pool).totalSupply(), amountToRemove);

        uint256 daiBalanceAfter = dai.balanceOf(alice);
        uint256 usdcBalanceAfter = usdc.balanceOf(alice);

        assertEq(daiBalanceAfter - daiBalanceBefore, amountOutAfterFee, "Ending DAI balance wrong");
        assertEq(usdcBalanceAfter - usdcBalanceBefore, amountOutAfterFee, "Ending USDC balance wrong");

        (, , uint256[] memory poolBalancesAfter, ) = IPoolInfo(pool).getTokenInfo();
        assertEq(poolBalancesBefore[0] - poolBalancesAfter[0], amountOutAfterFee, "Ending balance[0] wrong (pool)");
        assertEq(poolBalancesBefore[1] - poolBalancesAfter[1], amountOutAfterFee, "Ending balance[1] wrong (pool)");
    }

    function testRecoveryModeBalances() public {
        // Add initial liquidity.
        uint256[] memory amountsIn = [uint256(defaultAmount), uint256(defaultAmount)].toMemoryArray();

        vm.prank(alice);
        (, uint256 bptAmountOut, ) = router.addLiquidityCustom(pool, amountsIn, bptAmount, false, bytes(""));

        // Raw and live should be in sync.
        assertRawAndLiveBalanceRelationship(true);

        // Put pool in recovery mode.
        vault.manualEnableRecoveryMode(pool);

        uint256 initialSupply = IERC20(pool).totalSupply();
        uint256 amountToRemove = bptAmountOut / 2;
        uint256 daiBalanceBefore = dai.balanceOf(alice);
        uint256 usdcBalanceBefore = usdc.balanceOf(alice);

        (, , uint256[] memory poolBalancesBefore, ) = IPoolInfo(pool).getTokenInfo();

        // Do a recovery withdrawal.
        vm.prank(alice);
        router.removeLiquidityRecovery(pool, bptAmountOut / 2);

        uint256 bptAfter = IERC20(pool).balanceOf(alice);
        assertEq(bptAfter, amountToRemove); // this is half the BPT
        assertEq(initialSupply - IERC20(pool).totalSupply(), amountToRemove);

        uint256 daiBalanceAfter = dai.balanceOf(alice);
        uint256 usdcBalanceAfter = usdc.balanceOf(alice);

        assertEq(daiBalanceAfter - daiBalanceBefore, defaultAmount / 2, "Ending DAI balance wrong (alice)");
        assertEq(usdcBalanceAfter - usdcBalanceBefore, defaultAmount / 2, "Ending USDC balance wrong (alice)");

        (, , uint256[] memory poolBalancesAfter, ) = IPoolInfo(pool).getTokenInfo();
        assertEq(poolBalancesBefore[0] - poolBalancesAfter[0], defaultAmount / 2, "Ending balance[0] wrong (pool)");
        assertEq(poolBalancesBefore[1] - poolBalancesAfter[1], defaultAmount / 2, "Ending balance[1] wrong (pool)");

        // Raw and live should be out of sync.
        assertRawAndLiveBalanceRelationship(false);

        vault.manualDisableRecoveryMode(pool);

        // Raw and live should be back in sync.
        assertRawAndLiveBalanceRelationship(true);
    }

    function testRecoveryModeEmitTransferFail() public {
        // We only want a partial match of the call, triggered when BPT is burnt.
        vm.mockCallRevert(
            pool,
            abi.encodeWithSelector(BalancerPoolToken.emitTransfer.selector, alice, address(0)),
            bytes("")
        );
        testRecoveryModeBalances();
    }

    function testRecoveryModeEmitApprovalFail() public {
        // Revoke infinite approval so that the event is emitted.
        vm.prank(alice);
        IERC20(pool).approve(address(router), type(uint256).max - 1);

        // We only want a partial match of the call, triggered when BPT is burnt.
        vm.mockCallRevert(
            pool,
            abi.encodeWithSelector(BalancerPoolToken.emitApproval.selector, alice, router),
            bytes("")
        );
        testRecoveryModeBalances();
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
