// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/console.sol";

import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";
import {
    LiquidityManagement,
    TokenConfig,
    PoolSwapParams,
    HookFlags,
    SwapKind,
    PoolRoleAccounts
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IVaultExplorer } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultExplorer.sol";
import { IAuthorizer } from "@balancer-labs/v3-interfaces/contracts/vault/IAuthorizer.sol";
import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { StableSurgeHook } from "../../contracts/StableSurgeHook.sol";
import { StableSurgeMedianMathMock } from "../../contracts/test/StableSurgeMedianMathMock.sol";

contract StableSurgeHookTest is BaseVaultTest {
    using FixedPoint for uint256;

    uint256 constant DEFAULT_SURGE_THRESHOLD_PERCENTAGE = 0.3e18;

    StableSurgeMedianMathMock stableSurgeMedianMathMock = new StableSurgeMedianMathMock();
    StableSurgeHook stableSurgeHook;

    function setUp() public override {
        super.setUp();
        stableSurgeHook = new StableSurgeHook(
            vault,
            DEFAULT_SURGE_THRESHOLD_PERCENTAGE,
            IAuthorizer(address(0))
        ); //TODO: add authorizer
    }

    function testOnRegister() public {
        LiquidityManagement memory emptyLiquidityManagement;

        assertEq(stableSurgeHook.getSurgeThresholdPercentage(pool), 0, "Surge threshold percentage should be 0");

        vm.expectEmit();
        emit StableSurgeHook.StableSurgeHookExampleRegistered(pool);

        vm.prank(address(vault));
        stableSurgeHook.onRegister(msg.sender, pool, new TokenConfig[](0), emptyLiquidityManagement);

        assertEq(
            stableSurgeHook.getSurgeThresholdPercentage(pool),
            DEFAULT_SURGE_THRESHOLD_PERCENTAGE,
            "Surge threshold percentage should be DEFAULT_SURGE_THRESHOLD_PERCENTAGE"
        );
    }

    function testGetHookFlags() public view {
        HookFlags memory hookFlags = HookFlags({
            enableHookAdjustedAmounts: false,
            shouldCallBeforeInitialize: false,
            shouldCallAfterInitialize: false,
            shouldCallComputeDynamicSwapFee: true,
            shouldCallBeforeSwap: false,
            shouldCallAfterSwap: false,
            shouldCallBeforeAddLiquidity: false,
            shouldCallAfterAddLiquidity: false,
            shouldCallBeforeRemoveLiquidity: false,
            shouldCallAfterRemoveLiquidity: false
        });
        assertEq(
            abi.encode(stableSurgeHook.getHookFlags()),
            abi.encode(hookFlags),
            "Hook flags should be correct"
        );
    }

    function testGetDefaultSurgeThresholdPercentage() public view {
        assertEq(
            stableSurgeHook.getDefaultSurgeThresholdPercentage(),
            DEFAULT_SURGE_THRESHOLD_PERCENTAGE,
            "Default surge threshold percentage should be correct"
        );
    }

    function testChangeSurgeThresholdPercentage() public {
        uint256 newSurgeThresholdPercentage = 0.5e18;

        vm.expectEmit();
        emit StableSurgeHook.ThresholdSurgePercentageChanged(pool, newSurgeThresholdPercentage);

        PoolRoleAccounts memory poolRoleAccounts = PoolRoleAccounts({
            pauseManager: address(this),
            swapFeeManager: address(this),
            poolCreator: address(this)
        });
        vm.mockCall(
            address(vault),
            abi.encodeWithSelector(IVaultExplorer.getPoolRoleAccounts.selector, pool),
            abi.encode(poolRoleAccounts)
        );

        vm.prank(address(this));
        stableSurgeHook.setSurgeThresholdPercentage(pool, newSurgeThresholdPercentage);

        assertEq(
            stableSurgeHook.getSurgeThresholdPercentage(pool),
            newSurgeThresholdPercentage,
            "Surge threshold percentage should be newSurgeThresholdPercentage"
        );
    }

    function testChangeSurgeThresholdPercentageRevertIfValueIsGreaterThanOne() public {
        uint256 newSurgeThresholdPercentage = 1.1e18;

        PoolRoleAccounts memory poolRoleAccounts = PoolRoleAccounts({
            pauseManager: address(this),
            swapFeeManager: address(this),
            poolCreator: address(this)
        });
        vm.mockCall(
            address(vault),
            abi.encodeWithSelector(IVaultExplorer.getPoolRoleAccounts.selector, pool),
            abi.encode(poolRoleAccounts)
        );

        vm.expectRevert(StableSurgeHook.InvalidSurgeThresholdPercentage.selector);
        stableSurgeHook.setSurgeThresholdPercentage(pool, newSurgeThresholdPercentage);
    }

    function testChangeSurgeThresholdPercentageRevertIfSenderIsNotFeeManager() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        stableSurgeHook.setSurgeThresholdPercentage(pool, 1e18);
    }

    function testGetSurgeFeePercentage() public view {
        uint256 numTokens = 8;
        uint256[] memory balances = new uint256[](numTokens);

        uint256 amountGivenScaled18 = 1e18;
        uint256 tokenIn = 0;
        uint256 tokenOut = 7;

        balances[0] = 1e18;
        balances[1] = 1e18;
        balances[2] = 1e18;
        balances[3] = 10000e18;
        balances[4] = 2e18;
        balances[5] = 3e18;
        balances[6] = 1e18;
        balances[7] = 1e18;

        PoolSwapParams memory params = PoolSwapParams({
            kind: SwapKind.EXACT_IN,
            indexIn: tokenIn,
            indexOut: tokenOut,
            amountGivenScaled18: amountGivenScaled18,
            balancesScaled18: balances,
            router: address(0),
            userData: bytes("")
        });
        uint256 surgeThresholdPercentage = DEFAULT_SURGE_THRESHOLD_PERCENTAGE;
        uint256 staticFeePercentage = 1e16;

        uint256 surgeFeePercentage = stableSurgeHook.getSurgeFeePercentage(
            params,
            surgeThresholdPercentage,
            staticFeePercentage
        );

        uint256[] memory newBalances = new uint256[](numTokens);
        for (uint256 i = 0; i < numTokens; ++i) {
            newBalances[i] = balances[i];
        }
        newBalances[tokenIn] += amountGivenScaled18;
        newBalances[tokenOut] -= amountGivenScaled18;

        uint256 newTotalImbalance = stableSurgeMedianMathMock.calculateImbalance(newBalances);
        uint expectedFee = staticFeePercentage +
            (stableSurgeHook.MAX_SURGE_FEE_PERCENTAGE() - staticFeePercentage).mulDown(
                (newTotalImbalance - surgeThresholdPercentage).divDown(surgeThresholdPercentage.complement())
            );

        assertEq(surgeFeePercentage, expectedFee, "Surge fee percentage should be expectedFee");
    }

    function testGetSurgeFeePercentageWhenNewTotalImbalanceIsZero() public view {
        uint256 numTokens = 8;
        uint256[] memory balances = new uint256[](numTokens);
        for (uint256 i = 0; i < numTokens; ++i) {
            balances[i] = 1e18;
        }

        uint256 amountGivenScaled18 = 1e18;
        uint256 tokenIn = 0;
        uint256 tokenOut = 7;

        PoolSwapParams memory params = PoolSwapParams({
            kind: SwapKind.EXACT_IN,
            indexIn: tokenIn,
            indexOut: tokenOut,
            amountGivenScaled18: amountGivenScaled18,
            balancesScaled18: balances,
            router: address(0),
            userData: bytes("")
        });
        uint256 surgeThresholdPercentage = DEFAULT_SURGE_THRESHOLD_PERCENTAGE;
        uint256 staticFeePercentage = 1e16;

        uint256 surgeFeePercentage = stableSurgeHook.getSurgeFeePercentage(
            params,
            surgeThresholdPercentage,
            staticFeePercentage
        );

        assertEq(surgeFeePercentage, staticFeePercentage, "Surge fee percentage should be staticFeePercentage");
    }

    function testGetSurgeFeePercentageWhenNewTotalImbalanceLesOrEqOld() public view {
        uint256 numTokens = 8;
        uint256[] memory balances = new uint256[](numTokens);
        balances[0] = 1e18;
        balances[1] = 1e18;
        balances[2] = 1e18;
        balances[3] = 10000e18;
        balances[4] = 2e18;
        balances[5] = 3e18;
        balances[6] = 1e18;
        balances[7] = 1e18;

        uint256 amountGivenScaled18 = 0;
        uint256 tokenIn = 0;
        uint256 tokenOut = 7;

        PoolSwapParams memory params = PoolSwapParams({
            kind: SwapKind.EXACT_IN,
            indexIn: tokenIn,
            indexOut: tokenOut,
            amountGivenScaled18: amountGivenScaled18,
            balancesScaled18: balances,
            router: address(0),
            userData: bytes("")
        });
        uint256 surgeThresholdPercentage = DEFAULT_SURGE_THRESHOLD_PERCENTAGE;
        uint256 staticFeePercentage = 1e16;

        uint256 surgeFeePercentage = stableSurgeHook.getSurgeFeePercentage(
            params,
            surgeThresholdPercentage,
            staticFeePercentage
        );

        assertEq(surgeFeePercentage, staticFeePercentage, "Surge fee percentage should be staticFeePercentage");
    }

    function testGetSurgeFeePercentageWhenNewTotalImbalanceLessOrEqThreshold() public view {
        uint256 numTokens = 8;
        uint256[] memory balances = new uint256[](numTokens);
        balances[0] = 1e18;
        balances[1] = 1e18;
        balances[2] = 1e18;
        balances[3] = 1e18;
        balances[4] = 2e18;
        balances[5] = 3e18;
        balances[6] = 1e18;
        balances[7] = 1e18;

        uint256 amountGivenScaled18 = 0;
        uint256 tokenIn = 0;
        uint256 tokenOut = 7;

        PoolSwapParams memory params = PoolSwapParams({
            kind: SwapKind.EXACT_IN,
            indexIn: tokenIn,
            indexOut: tokenOut,
            amountGivenScaled18: amountGivenScaled18,
            balancesScaled18: balances,
            router: address(0),
            userData: bytes("")
        });
        uint256 surgeThresholdPercentage = DEFAULT_SURGE_THRESHOLD_PERCENTAGE;
        uint256 staticFeePercentage = 1e16;

        uint256 surgeFeePercentage = stableSurgeHook.getSurgeFeePercentage(
            params,
            surgeThresholdPercentage,
            staticFeePercentage
        );

        assertEq(surgeFeePercentage, staticFeePercentage, "Surge fee percentage should be staticFeePercentage");
    }
}
