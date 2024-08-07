// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { BaseHooksMock } from "../../contracts/test/BaseHooksMock.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract BaseHooksTest is BaseVaultTest {
    BaseHooksMock internal testHook;

    function setUp() public override {
        BaseVaultTest.setUp();

        // Not using PoolHooksMock address because onRegister of BaseHooks fails, so the test does not run.
        testHook = new BaseHooksMock(IVault(address(vault)));
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

    function testOnBeforeInitialize() public {
        uint256[] memory exactAmountsIn;

        vm.prank(address(vault));
        assertFalse(testHook.onBeforeInitialize(exactAmountsIn, bytes("")), "onBeforeInitialize should be false");
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

        // `hookAdjustedAmounts` should not be used in case result is false, so make sure it's an empty value.
        assertEq(hookAdjustedAmounts.length, 0, "hookAdjustedAmounts is not empty");
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

        // `hookAdjustedAmounts` should not be used in case result is false, so make sure it's an empty value.
        assertEq(hookAdjustedAmounts.length, 0, "hookAdjustedAmounts is not empty");
    }

    function testOnBeforeSwap() public {
        PoolSwapParams memory params;

        vm.prank(address(vault));
        assertFalse(testHook.onBeforeSwap(params, address(0)), "onBeforeSwap should be false");
    }

    function testOnAfterSwap() public {
        AfterSwapParams memory params;

        vm.prank(address(vault));
        (bool success, uint256 hookAdjustedAmount) = testHook.onAfterSwap(params);

        assertFalse(success, "onAfterSwap should be false");
        // `hookAdjustedAmount` should not be used in case result is false, so make sure it's zero.
        assertEq(hookAdjustedAmount, 0, "hookAdjustedAmount is not zero");
    }

    function testOnComputeDynamicSwapFeePercentage() public {
        PoolSwapParams memory params;
        uint256 staticSwapFeePercentage;

        vm.prank(address(vault));
        (bool success, uint256 newFeePercentage) = testHook.onComputeDynamicSwapFeePercentage(
            params,
            address(0),
            staticSwapFeePercentage
        );

        assertFalse(success, "onComputeDynamicSwapFeePercentage should be false");
        // `newFeePercentage` should not be used in case result is false, so make sure it's zero.
        assertEq(newFeePercentage, 0, "newFeePercentage is not zero");
    }
}
