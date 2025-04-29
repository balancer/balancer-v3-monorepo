// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";

import { IStableSurgeHook } from "@balancer-labs/v3-interfaces/contracts/pool-hooks/IStableSurgeHook.sol";
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
import { ScalingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ScalingHelpers.sol";
import { StablePool } from "@balancer-labs/v3-pool-stable/contracts/StablePool.sol";

import { StableSurgeHookDeployer } from "./utils/StableSurgeHookDeployer.sol";
import { StableSurgeHook } from "../../contracts/StableSurgeHook.sol";
import { StableSurgeMedianMathMock } from "../../contracts/test/StableSurgeMedianMathMock.sol";

contract StableSurgeHookUnitTest is BaseVaultTest, StableSurgeHookDeployer {
    using FixedPoint for uint256;

    uint256 constant MIN_TOKENS = 2;
    uint256 constant MAX_TOKENS = 8;

    uint256 constant STATIC_FEE_PERCENTAGE = 1e16;

    string internal version = "Stable Surge Hook Vx";

    StableSurgeMedianMathMock stableSurgeMedianMathMock = new StableSurgeMedianMathMock();
    StableSurgeHook stableSurgeHook;
    LiquidityManagement defaultLiquidityManagement;

    function setUp() public override {
        super.setUp();

        vm.prank(address(poolFactory));
        stableSurgeHook = deployStableSurgeHook(
            vault,
            DEFAULT_MAX_SURGE_FEE_PERCENTAGE,
            DEFAULT_SURGE_THRESHOLD_PERCENTAGE,
            version
        );

        authorizer.grantRole(
            IAuthentication(address(stableSurgeHook)).getActionId(IStableSurgeHook.setMaxSurgeFeePercentage.selector),
            admin
        );
    }

    function testVersion() public view {
        assertEq(stableSurgeHook.version(), version, "Incorrect version");
    }

    function testOnRegister() public {
        assertEq(stableSurgeHook.getSurgeThresholdPercentage(pool), 0, "Surge threshold percentage should be 0");

        vm.expectEmit();
        emit IStableSurgeHook.StableSurgeHookRegistered(pool, poolFactory);
        _registerPool();

        assertEq(
            stableSurgeHook.getSurgeThresholdPercentage(pool),
            DEFAULT_SURGE_THRESHOLD_PERCENTAGE,
            "Surge threshold percentage should be DEFAULT_SURGE_THRESHOLD_PERCENTAGE"
        );
    }

    function _registerPool() private {
        LiquidityManagement memory emptyLiquidityManagement;

        vm.prank(address(vault));
        stableSurgeHook.onRegister(poolFactory, pool, new TokenConfig[](0), emptyLiquidityManagement);
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
            shouldCallAfterAddLiquidity: true,
            shouldCallBeforeRemoveLiquidity: false,
            shouldCallAfterRemoveLiquidity: true
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
        emit IStableSurgeHook.ThresholdSurgePercentageChanged(pool, newSurgeThresholdPercentage);

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

        vm.expectRevert(IStableSurgeHook.InvalidPercentage.selector);
        stableSurgeHook.setSurgeThresholdPercentage(pool, newSurgeThresholdPercentage);
    }

    function testChangeSurgeThresholdPercentageRevertIfSenderIsNotFeeManager() public {
        PoolRoleAccounts memory poolRoleAccounts = PoolRoleAccounts({
            pauseManager: address(0x01),
            swapFeeManager: address(0x01),
            poolCreator: address(0x01)
        });
        vm.mockCall(
            address(vault),
            abi.encodeWithSelector(IVaultExplorer.getPoolRoleAccounts.selector, pool),
            abi.encode(poolRoleAccounts)
        );

        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        stableSurgeHook.setSurgeThresholdPercentage(pool, 1e18);
    }

    function testChangeSurgeThresholdPercentageRevertIfFeeManagerIsZero() public {
        PoolRoleAccounts memory poolRoleAccounts = PoolRoleAccounts({
            pauseManager: address(0x00),
            swapFeeManager: address(0x00),
            poolCreator: address(0x00)
        });
        vm.mockCall(
            address(vault),
            abi.encodeWithSelector(IVaultExplorer.getPoolRoleAccounts.selector, pool),
            abi.encode(poolRoleAccounts)
        );

        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        stableSurgeHook.setSurgeThresholdPercentage(pool, 1e18);
    }

    function testGetSurgeFeePercentage_MaxSurgeSmallerThanStatic() public {
        // Set a small max surge fee percentage.
        uint256 smallMaxSurgeFee = 1e16; // 1%
        vm.prank(admin);
        stableSurgeHook.setMaxSurgeFeePercentage(pool, smallMaxSurgeFee);

        // Set a larger static fee percentage.
        uint256 staticFeePercentage = 2e16; // 2%
        vault.manualUnsafeSetStaticSwapFeePercentage(pool, staticFeePercentage);

        // Create an unbalanced state to mock an imbalance in the pool. This would normally trigger surge pricing and
        // revert due to a math underflow, but the surge logic is currently blocked because maxSurgeFeePercentage <
        // staticFeePercentage.
        uint256[] memory balances = new uint256[](2);
        balances[0] = poolInitAmount / 10;
        balances[1] = poolInitAmount;

        // Create swap params that would normally trigger surge pricing.
        PoolSwapParams memory params = PoolSwapParams({
            kind: SwapKind.EXACT_IN,
            indexIn: 0,
            indexOut: 1,
            amountGivenScaled18: poolInitAmount / 2,
            balancesScaled18: balances,
            router: address(0),
            userData: bytes("")
        });

        // Even though we're in a surging state, we should get back the static fee since it's larger than the max
        // surge fee.
        uint256 surgeFeePercentage = stableSurgeHook.getSurgeFeePercentage(params, pool, staticFeePercentage);
        assertEq(surgeFeePercentage, staticFeePercentage, "Should return static fee percentage");
    }

    function testGetSurgeFeePercentage__Fuzz(
        uint256 length,
        uint256 indexIn,
        uint256 indexOut,
        uint256 amountGivenScaled18,
        uint256 kindRaw,
        uint256[8] memory rawBalances
    ) public {
        _registerPool();

        SwapKind kind;
        uint256[] memory balances;

        (length, indexIn, indexOut, amountGivenScaled18, kind, balances) = _boundValues(
            length,
            indexIn,
            indexOut,
            amountGivenScaled18,
            kindRaw,
            rawBalances
        );
        PoolSwapParams memory swapParams = _buildSwapParams(indexIn, indexOut, amountGivenScaled18, kind, balances);
        uint256 surgeFeePercentage = stableSurgeHook.getSurgeFeePercentage(swapParams, pool, STATIC_FEE_PERCENTAGE);
        uint256[] memory newBalances = _computeNewBalances(swapParams);
        uint256 expectedFee = _calculateFee(
            stableSurgeMedianMathMock.calculateImbalance(newBalances),
            stableSurgeMedianMathMock.calculateImbalance(balances)
        );
        assertEq(surgeFeePercentage, expectedFee, "Surge fee percentage should be expectedFee");
    }

    function testOnComputeDynamicSwapFeePercentage__Fuzz(
        uint256 length,
        uint256 indexIn,
        uint256 indexOut,
        uint256 amountGivenScaled18,
        uint256 kindRaw,
        uint256[8] memory rawBalances
    ) public {
        _registerPool();

        SwapKind kind;
        uint256[] memory balances;

        (length, indexIn, indexOut, amountGivenScaled18, kind, balances) = _boundValues(
            length,
            indexIn,
            indexOut,
            amountGivenScaled18,
            kindRaw,
            rawBalances
        );

        PoolSwapParams memory swapParams = _buildSwapParams(indexIn, indexOut, amountGivenScaled18, kind, balances);
        vm.prank(address(vault));
        (bool success, uint256 surgeFeePercentage) = stableSurgeHook.onComputeDynamicSwapFeePercentage(
            swapParams,
            pool,
            STATIC_FEE_PERCENTAGE
        );
        assertTrue(success, "onComputeDynamicSwapFeePercentage should return true");

        uint256[] memory newBalances = _computeNewBalances(swapParams);
        uint256 expectedFee = _calculateFee(
            stableSurgeMedianMathMock.calculateImbalance(newBalances),
            stableSurgeMedianMathMock.calculateImbalance(balances)
        );

        assertEq(surgeFeePercentage, expectedFee, "Surge fee percentage should be expectedFee");
    }

    function testGetSurgeFeePercentageWhenNewTotalImbalanceIsZero() public {
        _registerPool();

        uint256 numTokens = 8;
        uint256[] memory balances = new uint256[](numTokens);
        for (uint256 i = 0; i < numTokens; ++i) {
            balances[i] = 1e18;
        }
        uint256 indexIn = 0;
        uint256 indexOut = MAX_TOKENS - 1;
        balances[indexIn] = 0;
        balances[indexOut] = 2e18;

        uint256 surgeFeePercentage = stableSurgeHook.getSurgeFeePercentage(
            _buildSwapParams(indexIn, indexOut, 1e18, SwapKind.EXACT_IN, balances),
            pool,
            STATIC_FEE_PERCENTAGE
        );

        assertEq(surgeFeePercentage, STATIC_FEE_PERCENTAGE, "Surge fee percentage should be staticFeePercentage");
    }

    function testGetSurgeFeePercentageWhenNewTotalImbalanceLesOrEqOld() public {
        _registerPool();

        uint256 numTokens = 8;
        uint256[] memory balances = new uint256[](numTokens);
        for (uint256 i = 0; i < numTokens; ++i) {
            balances[i] = 1e18;
        }
        balances[3] = 10000e18;

        uint256 surgeFeePercentage = stableSurgeHook.getSurgeFeePercentage(
            _buildSwapParams(0, MAX_TOKENS - 1, 0, SwapKind.EXACT_IN, balances),
            pool,
            STATIC_FEE_PERCENTAGE
        );
        assertEq(surgeFeePercentage, STATIC_FEE_PERCENTAGE, "Surge fee percentage should be staticFeePercentage");
    }

    function testGetSurgeFeePercentageWhenNewTotalImbalanceLessOrEqThreshold() public {
        _registerPool();

        uint256 numTokens = 8;
        uint256[] memory balances = new uint256[](numTokens);
        for (uint256 i = 0; i < numTokens; ++i) {
            balances[i] = 1e18;
        }
        balances[4] = 2e18;
        balances[5] = 2e18;

        uint256 surgeFeePercentage = stableSurgeHook.getSurgeFeePercentage(
            _buildSwapParams(0, MAX_TOKENS - 1, 1, SwapKind.EXACT_IN, balances),
            pool,
            STATIC_FEE_PERCENTAGE
        );
        assertEq(surgeFeePercentage, STATIC_FEE_PERCENTAGE, "Surge fee percentage should be staticFeePercentage");
    }

    function _boundValues(
        uint256 lengthRaw,
        uint256 indexInRaw,
        uint256 indexOutRaw,
        uint256 amountGivenScaled18Raw,
        uint256 kindRaw,
        uint256[8] memory balancesRaw
    )
        internal
        pure
        returns (
            uint256 length,
            uint256 indexIn,
            uint256 indexOut,
            uint256 amountGivenScaled18,
            SwapKind kind,
            uint256[] memory balances
        )
    {
        length = bound(lengthRaw, MIN_TOKENS, MAX_TOKENS);
        balances = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            balances[i] = bound(balancesRaw[i], 1, MAX_UINT128);
        }

        indexIn = bound(indexInRaw, 0, length - 1);
        indexOut = bound(indexOutRaw, 0, length - 1);
        if (indexIn == indexOut) {
            indexOut = (indexOut + 1) % length;
        }

        kind = SwapKind(bound(kindRaw, 0, 1));

        amountGivenScaled18 = bound(amountGivenScaled18Raw, 1, balances[indexOut]);
    }

    function _buildSwapParams(
        uint256 indexIn,
        uint256 indexOut,
        uint256 amountGivenScaled18,
        SwapKind kind,
        uint256[] memory balances
    ) internal pure returns (PoolSwapParams memory) {
        return
            PoolSwapParams({
                kind: kind,
                indexIn: indexIn,
                indexOut: indexOut,
                amountGivenScaled18: amountGivenScaled18,
                balancesScaled18: balances,
                router: address(0),
                userData: bytes("")
            });
    }

    function _computeNewBalances(PoolSwapParams memory params) internal view returns (uint256[] memory) {
        uint256 amountCalculatedScaled18 = StablePool(pool).onSwap(params);

        uint256[] memory newBalances = new uint256[](params.balancesScaled18.length);
        ScalingHelpers.copyToArray(params.balancesScaled18, newBalances);

        if (params.kind == SwapKind.EXACT_IN) {
            newBalances[params.indexIn] += params.amountGivenScaled18;
            newBalances[params.indexOut] -= amountCalculatedScaled18;
        } else {
            newBalances[params.indexIn] += amountCalculatedScaled18;
            newBalances[params.indexOut] -= params.amountGivenScaled18;
        }

        return newBalances;
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
            (stableSurgeHook.getMaxSurgeFeePercentage(pool) - STATIC_FEE_PERCENTAGE).mulDown(
                (newTotalImbalance - DEFAULT_SURGE_THRESHOLD_PERCENTAGE).divDown(
                    DEFAULT_SURGE_THRESHOLD_PERCENTAGE.complement()
                )
            );
    }
}
