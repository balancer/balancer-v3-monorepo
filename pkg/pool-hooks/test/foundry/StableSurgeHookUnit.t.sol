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
import { IBasePoolFactory } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePoolFactory.sol";
import { IVaultExplorer } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultExplorer.sol";
import { IAuthorizer } from "@balancer-labs/v3-interfaces/contracts/vault/IAuthorizer.sol";
import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { StableSurgeHook } from "../../contracts/StableSurgeHook.sol";
import { StableSurgeMedianMathMock } from "../../contracts/test/StableSurgeMedianMathMock.sol";

contract StableSurgeHookUnitTest is BaseVaultTest {
    using FixedPoint for uint256;

    uint256 constant MIN_TOKENS = 2;
    uint256 constant MAX_TOKENS = 8;
    uint256 constant DEFAULT_SURGE_THRESHOLD_PERCENTAGE = 0.3e18;
    uint256 constant STATIC_FEE_PERCENTAGE = 1e16;

    StableSurgeMedianMathMock stableSurgeMedianMathMock = new StableSurgeMedianMathMock();
    StableSurgeHook stableSurgeHook;

    // Set the authorizer and the pool factory to msg.sender, and then mock them
    IBasePoolFactory poolFactory = IBasePoolFactory(address(msg.sender));

    LiquidityManagement defaultLiquidityManagement;

    function setUp() public override {
        super.setUp();
        stableSurgeHook = new StableSurgeHook(
            vault,
            address(poolFactory),
            authorizer,
            DEFAULT_SURGE_THRESHOLD_PERCENTAGE
        );
    }

    function testOnRegister() public {
        assertEq(stableSurgeHook.getSurgeThresholdPercentage(pool), 0, "Surge threshold percentage should be 0");

        vm.expectEmit();
        emit StableSurgeHook.StableSurgeHookExampleRegistered(pool, address(poolFactory));

        vm.mockCall(
            address(poolFactory),
            abi.encodeWithSelector(IBasePoolFactory.isPoolFromFactory.selector, pool),
            abi.encode(true)
        );
        vm.prank(address(vault));
        assertEq(
            stableSurgeHook.onRegister(address(poolFactory), pool, new TokenConfig[](0), defaultLiquidityManagement),
            true,
            "onRegister should return true"
        );

        assertEq(
            stableSurgeHook.getSurgeThresholdPercentage(pool),
            DEFAULT_SURGE_THRESHOLD_PERCENTAGE,
            "Surge threshold percentage should be DEFAULT_SURGE_THRESHOLD_PERCENTAGE"
        );
    }

    function testOnRegisterWithIncorrectFactory() public {
        assertEq(stableSurgeHook.getSurgeThresholdPercentage(pool), 0, "Surge threshold percentage should be 0");

        vm.prank(address(vault));
        assertEq(
            stableSurgeHook.onRegister(address(0), pool, new TokenConfig[](0), defaultLiquidityManagement),
            false,
            "onRegister should return false"
        );

        assertEq(stableSurgeHook.getSurgeThresholdPercentage(pool), 0, "Surge threshold percentage should be 0");
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
        assertEq(abi.encode(stableSurgeHook.getHookFlags()), abi.encode(hookFlags), "Hook flags should be correct");
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

    function testChangeSurgeThresholdPercentageAuthorizer() public {
        uint256 newSurgeThresholdPercentage = 0.5e18;

        authorizer.grantRole(vault.getActionId(StableSurgeHook.setSurgeThresholdPercentage.selector), address(this));

        vm.expectEmit();
        emit StableSurgeHook.ThresholdSurgePercentageChanged(pool, newSurgeThresholdPercentage);
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

    function testChangeSurgeThresholdPercentageRevertIfSenderIsNotFeeManagerAndNotAuthorizer() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);

        stableSurgeHook.setSurgeThresholdPercentage(pool, 1e18);
    }

    function testGetSurgeFeePercentage_Fuzz(
        uint256 length,
        uint256 tokenIn,
        uint256 tokenOut,
        uint256 amountGivenScaled18,
        uint256[8] memory rawBalances
    ) public view {
        uint256[] memory balances;
        (length, tokenIn, tokenOut, amountGivenScaled18, balances) = _boundValues(
            length,
            tokenIn,
            tokenOut,
            amountGivenScaled18,
            rawBalances
        );

        uint256 surgeFeePercentage = stableSurgeHook.getSurgeFeePercentage(
            _buildSwapParams(tokenIn, tokenOut, amountGivenScaled18, balances),
            DEFAULT_SURGE_THRESHOLD_PERCENTAGE,
            STATIC_FEE_PERCENTAGE
        );

        uint256[] memory newBalances = new uint256[](length);
        for (uint256 i = 0; i < length; ++i) {
            newBalances[i] = balances[i];
        }
        newBalances[tokenIn] += amountGivenScaled18;
        newBalances[tokenOut] -= amountGivenScaled18;

        uint256 expectedFee = _calculateFee(
            stableSurgeMedianMathMock.calculateImbalance(newBalances),
            stableSurgeMedianMathMock.calculateImbalance(balances)
        );

        assertEq(surgeFeePercentage, expectedFee, "Surge fee percentage should be expectedFee");
    }

    function testOnComputeDynamicSwapFeePercentage_Fuzz(
        uint256 length,
        uint256 tokenIn,
        uint256 tokenOut,
        uint256 amountGivenScaled18,
        uint256[8] memory rawBalances
    ) public {
        uint256[] memory balances;
        (length, tokenIn, tokenOut, amountGivenScaled18, balances) = _boundValues(
            length,
            tokenIn,
            tokenOut,
            amountGivenScaled18,
            rawBalances
        );

        vm.mockCall(
            address(poolFactory),
            abi.encodeWithSelector(IBasePoolFactory.isPoolFromFactory.selector, pool),
            abi.encode(true)
        );

        vm.prank(address(vault));
        stableSurgeHook.onRegister(address(poolFactory), pool, new TokenConfig[](0), defaultLiquidityManagement);

        vm.prank(address(vault));
        (bool success, uint256 surgeFeePercentage) = stableSurgeHook.onComputeDynamicSwapFeePercentage(
            _buildSwapParams(tokenIn, tokenOut, amountGivenScaled18, balances),
            pool,
            STATIC_FEE_PERCENTAGE
        );

        assertTrue(success, "onComputeDynamicSwapFeePercentage should return true");

        uint256[] memory newBalances = new uint256[](length);
        for (uint256 i = 0; i < length; ++i) {
            newBalances[i] = balances[i];
        }
        newBalances[tokenIn] += amountGivenScaled18;
        newBalances[tokenOut] -= amountGivenScaled18;

        uint256 expectedFee = _calculateFee(
            stableSurgeMedianMathMock.calculateImbalance(newBalances),
            stableSurgeMedianMathMock.calculateImbalance(balances)
        );

        assertEq(surgeFeePercentage, expectedFee, "Surge fee percentage should be expectedFee");
    }

    function testGetSurgeFeePercentageWhenNewTotalImbalanceIsZero() public view {
        uint256 numTokens = 8;
        uint256[] memory balances = new uint256[](numTokens);
        for (uint256 i = 0; i < numTokens; ++i) {
            balances[i] = 1e18;
        }

        uint256 surgeFeePercentage = stableSurgeHook.getSurgeFeePercentage(
            _buildSwapParams(0, MAX_TOKENS - 1, 1e18, balances),
            DEFAULT_SURGE_THRESHOLD_PERCENTAGE,
            STATIC_FEE_PERCENTAGE
        );

        assertEq(surgeFeePercentage, STATIC_FEE_PERCENTAGE, "Surge fee percentage should be staticFeePercentage");
    }

    function testGetSurgeFeePercentageWhenNewTotalImbalanceLesOrEqOld() public view {
        uint256 numTokens = 8;
        uint256[] memory balances = new uint256[](numTokens);
        for (uint256 i = 0; i < numTokens; ++i) {
            balances[i] = 1e18;
        }
        balances[3] = 10000e18;

        uint256 surgeFeePercentage = stableSurgeHook.getSurgeFeePercentage(
            _buildSwapParams(0, MAX_TOKENS - 1, 0, balances),
            DEFAULT_SURGE_THRESHOLD_PERCENTAGE,
            STATIC_FEE_PERCENTAGE
        );

        assertEq(surgeFeePercentage, STATIC_FEE_PERCENTAGE, "Surge fee percentage should be staticFeePercentage");
    }

    function testGetSurgeFeePercentageWhenNewTotalImbalanceLessOrEqThreshold() public view {
        uint256 numTokens = 8;
        uint256[] memory balances = new uint256[](numTokens);
        for (uint256 i = 0; i < numTokens; ++i) {
            balances[i] = 1e18;
        }
        balances[4] = 2e18;
        balances[5] = 2e18;

        uint256 surgeFeePercentage = stableSurgeHook.getSurgeFeePercentage(
            _buildSwapParams(0, MAX_TOKENS - 1, 1, balances),
            DEFAULT_SURGE_THRESHOLD_PERCENTAGE,
            STATIC_FEE_PERCENTAGE
        );

        assertEq(surgeFeePercentage, STATIC_FEE_PERCENTAGE, "Surge fee percentage should be staticFeePercentage");
    }

    function _boundValues(
        uint256 length,
        uint256 tokenIn,
        uint256 tokenOut,
        uint256 amountGivenScaled18,
        uint256[8] memory rawBalances
    ) internal pure returns (uint256, uint256, uint256, uint256, uint256[] memory) {
        length = bound(length, MIN_TOKENS, MAX_TOKENS);
        uint256[] memory balances = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            balances[i] = bound(rawBalances[i], 1, MAX_UINT128);
        }

        tokenIn = bound(tokenIn, 0, length - 1);
        tokenOut = bound(tokenOut, 0, length - 1);
        if (tokenIn == tokenOut) {
            tokenOut = (tokenOut + 1) % length;
        }

        amountGivenScaled18 = bound(amountGivenScaled18, 1, balances[tokenOut]);

        return (length, tokenIn, tokenOut, amountGivenScaled18, balances);
    }

    function _buildSwapParams(
        uint256 tokenIn,
        uint256 tokenOut,
        uint256 amountGivenScaled18,
        uint256[] memory balances
    ) internal pure returns (PoolSwapParams memory) {
        return
            PoolSwapParams({
                kind: SwapKind.EXACT_IN,
                indexIn: tokenIn,
                indexOut: tokenOut,
                amountGivenScaled18: amountGivenScaled18,
                balancesScaled18: balances,
                router: address(0),
                userData: bytes("")
            });
    }

    function _calculateFee(uint256 newTotalImbalance, uint256 oldTotalImbalance) internal view returns (uint256) {
        if (
            newTotalImbalance == 0 ||
            (newTotalImbalance <= oldTotalImbalance || newTotalImbalance <= DEFAULT_SURGE_THRESHOLD_PERCENTAGE)
        ) {
            return STATIC_FEE_PERCENTAGE;
        }

        return
            STATIC_FEE_PERCENTAGE +
            (stableSurgeHook.MAX_SURGE_FEE_PERCENTAGE() - STATIC_FEE_PERCENTAGE).mulDown(
                (newTotalImbalance - DEFAULT_SURGE_THRESHOLD_PERCENTAGE).divDown(
                    DEFAULT_SURGE_THRESHOLD_PERCENTAGE.complement()
                )
            );
    }
}
