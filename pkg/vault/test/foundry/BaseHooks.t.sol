// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { BaseHooks } from "../../contracts/BaseHooks.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract BaseHooksTest is BaseVaultTest {
    BaseHooks internal testHook;

    function setUp() public override {
        BaseVaultTest.setUp();

        // Not using poolHooksMock address because onRegister of BaseHooks fails, so the test does not run.
        testHook = new BaseHooks(IVault(address(vault)));
    }

    function testOnRegisterOnlyVault() public {
        TokenConfig[] memory tokenConfig;
        LiquidityManagement memory liquidityManagement;

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.SenderIsNotVault.selector, bob));
        testHook.onRegister(address(0), address(0), tokenConfig, liquidityManagement);
    }

    function testOnRegister() public {
        TokenConfig[] memory tokenConfig;
        LiquidityManagement memory liquidityManagement;

        vm.prank(address(vault));
        assertFalse(
            testHook.onRegister(address(0), address(0), tokenConfig, liquidityManagement),
            "onRegister should be false"
        );
    }

    function testGetHooksFlags() public view {
        IHooks.HookFlags memory flags = testHook.getHookFlags();

        assertFalse(flags.enableHookAdjustedAmounts, "enableHookAdjustedAmounts should be false");
        assertFalse(flags.shouldCallBeforeInitialize, "shouldCallBeforeInitialize should be false");
        assertFalse(flags.shouldCallAfterInitialize, "shouldCallAfterInitialize should be false");
        assertFalse(flags.shouldCallComputeDynamicSwapFee, "shouldCallComputeDynamicSwapFee should be false");
        assertFalse(flags.shouldCallBeforeSwap, "shouldCallBeforeSwap should be false");
        assertFalse(flags.shouldCallAfterSwap, "shouldCallAfterSwap should be false");
        assertFalse(flags.shouldCallBeforeAddLiquidity, "shouldCallBeforeAddLiquidity should be false");
        assertFalse(flags.shouldCallAfterAddLiquidity, "shouldCallAfterAddLiquidity should be false");
        assertFalse(flags.shouldCallBeforeRemoveLiquidity, "shouldCallBeforeRemoveLiquidity should be false");
        assertFalse(flags.shouldCallAfterRemoveLiquidity, "shouldCallAfterRemoveLiquidity should be false");
    }

    function testOnBeforeInitializeOnlyVault() public {
        uint256[] memory exactAmountsIn;

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.SenderIsNotVault.selector, bob));
        testHook.onBeforeInitialize(exactAmountsIn, bytes(""));
    }

    function testOnBeforeInitialize() public {
        uint256[] memory exactAmountsIn;

        vm.prank(address(vault));
        assertFalse(testHook.onBeforeInitialize(exactAmountsIn, bytes("")), "onBeforeInitialize should be false");
    }

    function testOnAfterInitializeOnlyVault() public {
        uint256[] memory exactAmountsIn;
        uint256 bptAmountOut;

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.SenderIsNotVault.selector, bob));
        testHook.onAfterInitialize(exactAmountsIn, bptAmountOut, bytes(""));
    }

    function testOnAfterInitialize() public {
        uint256[] memory exactAmountsIn;
        uint256 bptAmountOut;

        vm.prank(address(vault));
        assertFalse(
            testHook.onAfterInitialize(exactAmountsIn, bptAmountOut, bytes("")),
            "onAfterInitialize should be false"
        );
    }

    function testOnBeforeAddLiquidityOnlyVault() public {
        uint256[] memory maxAmountsInScaled18;
        uint256 minBptAmountOut;
        uint256[] memory balancesScaled18;

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.SenderIsNotVault.selector, bob));
        testHook.onBeforeAddLiquidity(
            address(0),
            address(0),
            AddLiquidityKind.CUSTOM,
            maxAmountsInScaled18,
            minBptAmountOut,
            balancesScaled18,
            bytes("")
        );
    }

    function testOnBeforeAddLiquidity() public {
        uint256[] memory maxAmountsInScaled18;
        uint256 minBptAmountOut;
        uint256[] memory balancesScaled18;

        vm.prank(address(vault));
        assertFalse(
            testHook.onBeforeAddLiquidity(
                address(0),
                address(0),
                AddLiquidityKind.CUSTOM,
                maxAmountsInScaled18,
                minBptAmountOut,
                balancesScaled18,
                bytes("")
            ),
            "onBeforeAddLiquidity should be false"
        );
    }

    function testOnAfterAddLiquidityOnlyVault() public {
        uint256[] memory amountsInScaled18;
        uint256[] memory amountsInRaw;
        uint256 bptAmountOut;
        uint256[] memory balancesScaled18;

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.SenderIsNotVault.selector, bob));
        testHook.onAfterAddLiquidity(
            address(0),
            address(0),
            AddLiquidityKind.CUSTOM,
            amountsInScaled18,
            amountsInRaw,
            bptAmountOut,
            balancesScaled18,
            bytes("")
        );
    }

    function testOnAfterAddLiquidity() public {
        uint256[] memory amountsInScaled18;
        uint256[] memory amountsInRaw;
        uint256 bptAmountOut;
        uint256[] memory balancesScaled18;

        vm.prank(address(vault));
        (bool result, uint256[] memory hookAdjustedAmounts) = testHook.onAfterAddLiquidity(
            address(0),
            address(0),
            AddLiquidityKind.CUSTOM,
            amountsInScaled18,
            amountsInRaw,
            bptAmountOut,
            balancesScaled18,
            bytes("")
        );
        assertFalse(result, "onAfterAddLiquidity should be false");

        // HookAdjustedAmounts should not be used in case result is false, so make sure it's an empty value.
        assertEq(hookAdjustedAmounts.length, 0, "hookAdjustedAmounts is not empty");
    }

    function testOnBeforeRemoveLiquidityOnlyVault() public {
        uint256 maxBptAmountIn;
        uint256[] memory minAmountsOutScaled18;
        uint256[] memory balancesScaled18;

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.SenderIsNotVault.selector, bob));
        testHook.onBeforeRemoveLiquidity(
            address(0),
            address(0),
            RemoveLiquidityKind.CUSTOM,
            maxBptAmountIn,
            minAmountsOutScaled18,
            balancesScaled18,
            bytes("")
        );
    }

    function testOnBeforeRemoveLiquidity() public {
        uint256 maxBptAmountIn;
        uint256[] memory minAmountsOutScaled18;
        uint256[] memory balancesScaled18;

        vm.prank(address(vault));
        assertFalse(
            testHook.onBeforeRemoveLiquidity(
                address(0),
                address(0),
                RemoveLiquidityKind.CUSTOM,
                maxBptAmountIn,
                minAmountsOutScaled18,
                balancesScaled18,
                bytes("")
            ),
            "onBeforeRemoveLiquidity should be false"
        );
    }

    function testOnAfterRemoveLiquidityOnlyVault() public {
        uint256 bptAmountIn;
        uint256[] memory amountsOutScaled18;
        uint256[] memory amountsOutRaw;
        uint256[] memory balancesScaled18;

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.SenderIsNotVault.selector, bob));
        testHook.onAfterRemoveLiquidity(
            address(0),
            address(0),
            RemoveLiquidityKind.CUSTOM,
            bptAmountIn,
            amountsOutScaled18,
            amountsOutRaw,
            balancesScaled18,
            bytes("")
        );
    }

    function testOnAfterRemoveLiquidity() public {
        uint256 bptAmountIn;
        uint256[] memory amountsOutScaled18;
        uint256[] memory amountsOutRaw;
        uint256[] memory balancesScaled18;

        vm.prank(address(vault));
        (bool result, uint256[] memory hookAdjustedAmounts) = testHook.onAfterRemoveLiquidity(
            address(0),
            address(0),
            RemoveLiquidityKind.CUSTOM,
            bptAmountIn,
            amountsOutScaled18,
            amountsOutRaw,
            balancesScaled18,
            bytes("")
        );
        assertFalse(result, "onAfterRemoveLiquidity should be false");

        // HookAdjustedAmounts should not be used in case result is false, so make sure it's an empty value.
        assertEq(hookAdjustedAmounts.length, 0, "hookAdjustedAmounts is not empty");
    }

    function testOnBeforeSwapOnlyVault() public {
        IBasePool.PoolSwapParams memory params;

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.SenderIsNotVault.selector, bob));
        testHook.onBeforeSwap(params, address(0));
    }

    function testOnBeforeSwap() public {
        IBasePool.PoolSwapParams memory params;

        vm.prank(address(vault));
        assertFalse(testHook.onBeforeSwap(params, address(0)), "onBeforeSwap should be false");
    }

    function testOnAfterSwapOnlyVault() public {
        IHooks.AfterSwapParams memory params;

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.SenderIsNotVault.selector, bob));
        testHook.onAfterSwap(params);
    }

    function testOnAfterSwap() public {
        IHooks.AfterSwapParams memory params;

        vm.prank(address(vault));
        (bool success, uint256 hookAdjustedAmount) = testHook.onAfterSwap(params);

        assertFalse(success, "onAfterSwap should be false");
        // HookAdjustedAmount should not be used in case result is false, so make sure it's zero.
        assertEq(hookAdjustedAmount, 0, "hookAdjustedAmount is not zero");
    }

    function testOnComputeDynamicFeeOnlyVault() public {
        IBasePool.PoolSwapParams memory params;
        uint256 staticSwapFeePercentage;

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.SenderIsNotVault.selector, bob));
        testHook.onComputeDynamicSwapFee(params, address(0), staticSwapFeePercentage);
    }

    function testOnComputeDynamicFee() public {
        IBasePool.PoolSwapParams memory params;
        uint256 staticSwapFeePercentage;

        vm.prank(address(vault));
        (bool success, uint256 newFee) = testHook.onComputeDynamicSwapFee(params, address(0), staticSwapFeePercentage);

        assertFalse(success, "onComputeDynamicSwapFee should be false");
        // newFee should not be used in case result is false, so make sure it's zero.
        assertEq(newFee, 0, "newFee is not zero");
    }
}
