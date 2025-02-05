// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Create2 } from "@openzeppelin/contracts/utils/Create2.sol";

import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import {
    LBPoolImmutableData,
    LBPoolDynamicData
} from "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPool.sol";
import {
    PoolConfig,
    PoolRoleAccounts,
    PoolSwapParams,
    SwapKind
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { LBPoolFactory } from "../../contracts/lbp/LBPoolFactory.sol";
import { LBPool } from "../../contracts/lbp/LBPool.sol";
import { BaseLBPTest } from "./utils/BaseLBPTest.sol";

contract LBPoolTest is BaseLBPTest {
    using ArrayHelpers for *;
    using FixedPoint for uint256;

    /********************************************************
                        Pool Constructor
    ********************************************************/

    function testCreatePoolLowProjectStartWeight() public {
        // Min weight is 1e16 (1%).
        uint256 wrongWeight = 0.5e16;

        // The MinWeight error thrown by the weighted pool is shadowed by the Create2 deployment error.
        vm.expectRevert(Create2.Create2FailedDeployment.selector);
        _deployAndInitializeWithCustomWeights(
            wrongWeight,
            wrongWeight.complement(),
            endWeights[projectIdx],
            endWeights[reserveIdx],
            uint32(block.timestamp + DEFAULT_START_OFFSET),
            uint32(block.timestamp + DEFAULT_END_OFFSET),
            DEFAULT_PROJECT_TOKENS_SWAP_IN
        );
    }

    function testCreatePoolLowReserveStartWeight() public {
        // Min weight is 1e16 (1%).
        uint256 wrongWeight = 0.5e16;

        // The MinWeight error thrown by the weighted pool is shadowed by the Create2 deployment error.
        vm.expectRevert(Create2.Create2FailedDeployment.selector);
        _deployAndInitializeWithCustomWeights(
            wrongWeight.complement(),
            wrongWeight,
            endWeights[projectIdx],
            endWeights[reserveIdx],
            uint32(block.timestamp + DEFAULT_START_OFFSET),
            uint32(block.timestamp + DEFAULT_END_OFFSET),
            DEFAULT_PROJECT_TOKENS_SWAP_IN
        );
    }

    function testCreatePoolLowProjectEndWeight() public {
        // Min weight is 1e16 (1%).
        uint256 wrongWeight = 0.5e16;

        // The MinWeight error thrown by the LBP is shadowed by the Create2 deployment error.
        vm.expectRevert(Create2.Create2FailedDeployment.selector);
        _deployAndInitializeWithCustomWeights(
            startWeights[projectIdx],
            startWeights[reserveIdx],
            wrongWeight,
            wrongWeight.complement(),
            uint32(block.timestamp + DEFAULT_START_OFFSET),
            uint32(block.timestamp + DEFAULT_END_OFFSET),
            DEFAULT_PROJECT_TOKENS_SWAP_IN
        );
    }

    function testCreatePoolLowReserveEndWeight() public {
        // Min weight is 1e16 (1%).
        uint256 wrongWeight = 0.5e16;

        // The MinWeight error thrown by the LBP is shadowed by the Create2 deployment error.
        vm.expectRevert(Create2.Create2FailedDeployment.selector);
        _deployAndInitializeWithCustomWeights(
            startWeights[projectIdx],
            startWeights[reserveIdx],
            wrongWeight.complement(),
            wrongWeight,
            uint32(block.timestamp + DEFAULT_START_OFFSET),
            uint32(block.timestamp + DEFAULT_END_OFFSET),
            DEFAULT_PROJECT_TOKENS_SWAP_IN
        );
    }

    function testCreatePoolNotNormalizedStartWeights() public {
        // The NormalizedWeightInvariant error thrown by the weighted pool is shadowed by the Create2 deployment error.
        vm.expectRevert(Create2.Create2FailedDeployment.selector);
        _deployAndInitializeWithCustomWeights(
            startWeights[projectIdx],
            startWeights[reserveIdx] - 1,
            endWeights[projectIdx],
            endWeights[reserveIdx],
            uint32(block.timestamp + DEFAULT_START_OFFSET),
            uint32(block.timestamp + DEFAULT_END_OFFSET),
            DEFAULT_PROJECT_TOKENS_SWAP_IN
        );
    }

    function testCreatePoolNotNormalizedEndWeights() public {
        // The NormalizedWeightInvariant error thrown by the LBP is shadowed by the Create2 deployment error.
        vm.expectRevert(Create2.Create2FailedDeployment.selector);
        _deployAndInitializeWithCustomWeights(
            startWeights[projectIdx],
            startWeights[reserveIdx],
            endWeights[projectIdx],
            endWeights[reserveIdx] - 1,
            uint32(block.timestamp + DEFAULT_START_OFFSET),
            uint32(block.timestamp + DEFAULT_END_OFFSET),
            DEFAULT_PROJECT_TOKENS_SWAP_IN
        );
    }

    function testCreatePoolTimeTravel() public {
        vm.expectRevert(Create2.Create2FailedDeployment.selector);
        _deployAndInitializeWithCustomWeights(
            startWeights[projectIdx],
            startWeights[reserveIdx],
            endWeights[projectIdx],
            endWeights[reserveIdx],
            uint32(block.timestamp + 200),
            uint32(block.timestamp + 100), // EndTime after StartTime, it should revert.
            DEFAULT_PROJECT_TOKENS_SWAP_IN
        );
    }

    function testCreatePoolEvent() public {
        uint32 startTime = uint32(block.timestamp + DEFAULT_START_OFFSET);
        uint32 endTime = uint32(block.timestamp + DEFAULT_END_OFFSET);

        vm.expectEmit();
        emit LBPool.GradualWeightUpdateScheduled(startTime, endTime, startWeights, endWeights);
        _deployAndInitializeWithCustomWeights(
            startWeights[projectIdx],
            startWeights[reserveIdx],
            endWeights[projectIdx],
            endWeights[reserveIdx],
            startTime,
            endTime,
            DEFAULT_PROJECT_TOKENS_SWAP_IN
        );
    }

    /********************************************************
                            Getters
    ********************************************************/

    function testGetTrustedRouter() public view {
        assertEq(LBPool(pool).getTrustedRouter(), address(router), "Wrong trusted router");
    }

    function testGetTrustedFactory() public view {
        assertEq(LBPool(pool).getTrustedFactory(), address(lbPoolFactory), "Wrong trusted factory");
    }

    function testGradualWeightUpdateParams() public {
        uint32 customStartTime = uint32(block.timestamp + 1);
        uint32 customEndTime = uint32(block.timestamp + 300);
        uint256[] memory customStartWeights = [uint256(22e16), uint256(78e16)].toMemoryArray();
        uint256[] memory customEndWeights = [uint256(65e16), uint256(35e16)].toMemoryArray();

        (address newPool, ) = _deployAndInitializeWithCustomWeights(
            customStartWeights[projectIdx],
            customStartWeights[reserveIdx],
            customEndWeights[projectIdx],
            customEndWeights[reserveIdx],
            customStartTime,
            customEndTime,
            DEFAULT_PROJECT_TOKENS_SWAP_IN
        );

        (
            uint256 poolStartTime,
            uint256 poolEndTime,
            uint256[] memory poolStartWeights,
            uint256[] memory poolEndWeights
        ) = LBPool(newPool).getGradualWeightUpdateParams();
        assertEq(poolStartTime, customStartTime, "Start time mismatch");
        assertEq(poolEndTime, customEndTime, "End time mismatch");

        assertEq(poolStartWeights.length, customStartWeights.length, "Start Weights length mismatch");
        assertEq(poolStartWeights[projectIdx], customStartWeights[projectIdx], "Project Start Weight mismatch");
        assertEq(poolStartWeights[reserveIdx], customStartWeights[reserveIdx], "Reserve Start Weight mismatch");

        assertEq(poolEndWeights.length, customEndWeights.length, "End Weights length mismatch");
        assertEq(poolEndWeights[projectIdx], customEndWeights[projectIdx], "Project End Weight mismatch");
        assertEq(poolEndWeights[reserveIdx], customEndWeights[reserveIdx], "Reserve End Weight mismatch");
    }

    function testIsSwapEnabled() public {
        uint32 startTime = uint32(block.timestamp + DEFAULT_START_OFFSET);
        uint32 endTime = uint32(block.timestamp + DEFAULT_END_OFFSET);

        assertFalse(LBPool(pool).isSwapEnabled(), "Swap should be disabled before start time");

        vm.warp(startTime + 1);
        assertTrue(LBPool(pool).isSwapEnabled(), "Swap should be enabled after start time");

        vm.warp(endTime + 1);
        assertFalse(LBPool(pool).isSwapEnabled(), "Swap should be disabled after end time");
    }

    function testIsProjectTokenSwapInEnabled() public {
        (address newPoolSwapDisabled, ) = _deployAndInitializeWithCustomWeights(
            startWeights[projectIdx],
            startWeights[reserveIdx],
            endWeights[projectIdx],
            endWeights[reserveIdx],
            uint32(block.timestamp + DEFAULT_START_OFFSET),
            uint32(block.timestamp + DEFAULT_END_OFFSET),
            false
        );

        assertFalse(LBPool(newPoolSwapDisabled).isProjectTokenSwapInEnabled(), "Swap of Project Token in is enabled");

        (address newPoolSwapEnabled, ) = _deployAndInitializeWithCustomWeights(
            startWeights[projectIdx],
            startWeights[reserveIdx],
            endWeights[projectIdx],
            endWeights[reserveIdx],
            uint32(block.timestamp + DEFAULT_START_OFFSET),
            uint32(block.timestamp + DEFAULT_END_OFFSET),
            true
        );

        assertTrue(LBPool(newPoolSwapEnabled).isProjectTokenSwapInEnabled(), "Swap of Project Token in is disabled");
    }

    function testGetWeightedPoolDynamicData() public {
        // This function is not implemented, since the weights are not immutable. So, it should revert.
        vm.expectRevert(LBPool.NotImplemented.selector);
        LBPool(pool).getWeightedPoolDynamicData();
    }

    function testGetWeightedPoolImmutableData() public {
        // This function is not implemented, since the weights are not immutable. So, it should revert.
        vm.expectRevert(LBPool.NotImplemented.selector);
        LBPool(pool).getWeightedPoolImmutableData();
    }

    function testGetLBPoolDynamicData() public view {
        LBPoolDynamicData memory data = LBPool(pool).getLBPoolDynamicData();

        uint256[] memory balancesLiveScaled18 = vault.getCurrentLiveBalances(pool);
        assertEq(data.balancesLiveScaled18.length, balancesLiveScaled18.length, "balancesLiveScaled18 length mismatch");
        assertEq(
            data.balancesLiveScaled18[projectIdx],
            balancesLiveScaled18[projectIdx],
            "Project token's balancesLiveScaled18 mismatch"
        );
        assertEq(
            data.balancesLiveScaled18[reserveIdx],
            balancesLiveScaled18[reserveIdx],
            "Reserve token's balancesLiveScaled18 mismatch"
        );

        assertEq(
            data.staticSwapFeePercentage,
            vault.getStaticSwapFeePercentage(pool),
            "staticSwapFeePercentage mismatch"
        );
        assertEq(data.totalSupply, LBPool(pool).totalSupply(), "TotalSupply mismatch");

        PoolConfig memory poolConfig = vault.getPoolConfig(pool);
        assertEq(data.isPoolInitialized, poolConfig.isPoolInitialized, "isPoolInitialized mismatch");
        assertEq(data.isPoolPaused, poolConfig.isPoolPaused, "isPoolInitialized mismatch");
        assertEq(data.isPoolInRecoveryMode, poolConfig.isPoolInRecoveryMode, "isPoolInitialized mismatch");

        assertEq(data.isSwapEnabled, LBPool(pool).isSwapEnabled(), "isSwapEnabled mismatch");

        assertEq(data.normalizedWeights.length, startWeights.length, "normalizedWeights length mismatch");
        assertEq(data.normalizedWeights[projectIdx], startWeights[projectIdx], "project weight mismatch");
        assertEq(data.normalizedWeights[reserveIdx], startWeights[reserveIdx], "reserve weight mismatch");
    }

    function testGetLBPoolDynamicDataWeightInterpolation() public {
        // Check initial weights
        LBPoolDynamicData memory initialData = LBPool(pool).getLBPoolDynamicData();
        assertEq(
            initialData.normalizedWeights[projectIdx],
            startWeights[projectIdx],
            "Initial project weight mismatch"
        );
        assertEq(
            initialData.normalizedWeights[reserveIdx],
            startWeights[reserveIdx],
            "Initial reserve weight mismatch"
        );

        // Warp to middle of weight update period
        vm.warp(block.timestamp + DEFAULT_START_OFFSET + 50);

        // Check interpolated weights
        LBPoolDynamicData memory midData = LBPool(pool).getLBPoolDynamicData();

        // Calculate expected weights (average between start and end weights)
        uint256 expectedProjectWeight = (startWeights[projectIdx] + endWeights[projectIdx]) / 2;
        uint256 expectedReserveWeight = (startWeights[reserveIdx] + endWeights[reserveIdx]) / 2;

        // Allow for small rounding differences
        assertEq(midData.normalizedWeights[projectIdx], expectedProjectWeight, "Interpolated project weight mismatch");
        assertEq(midData.normalizedWeights[reserveIdx], expectedReserveWeight, "Interpolated reserve weight mismatch");

        // Warp to end of weight update period
        vm.warp(block.timestamp + DEFAULT_END_OFFSET);

        // Check final weights
        LBPoolDynamicData memory finalData = LBPool(pool).getLBPoolDynamicData();
        assertEq(finalData.normalizedWeights[projectIdx], endWeights[projectIdx], "Final project weight mismatch");
        assertEq(finalData.normalizedWeights[reserveIdx], endWeights[reserveIdx], "Final reserve weight mismatch");
    }

    function testGetLBPoolImmutableData() public view {
        LBPoolImmutableData memory data = LBPool(pool).getLBPoolImmutableData();

        // Check tokens array matches pool tokens
        IERC20[] memory poolTokens = vault.getPoolTokens(pool);
        assertEq(data.tokens.length, poolTokens.length, "tokens length mismatch");
        assertEq(address(data.tokens[projectIdx]), address(poolTokens[projectIdx]), "Project token mismatch");
        assertEq(address(data.tokens[reserveIdx]), address(poolTokens[reserveIdx]), "Reserve token mismatch");

        // Check decimal scaling factors
        (uint256[] memory decimalScalingFactors, ) = vault.getPoolTokenRates(pool);
        assertEq(
            data.decimalScalingFactors.length,
            decimalScalingFactors.length,
            "decimalScalingFactors length mismatch"
        );
        assertEq(
            data.decimalScalingFactors[projectIdx],
            decimalScalingFactors[projectIdx],
            "Project scaling factor mismatch"
        );
        assertEq(
            data.decimalScalingFactors[reserveIdx],
            decimalScalingFactors[reserveIdx],
            "Reserve scaling factor mismatch"
        );

        // Check project token swap in setting
        assertEq(
            data.isProjectTokenSwapInEnabled,
            DEFAULT_PROJECT_TOKENS_SWAP_IN,
            "Project token swap in setting mismatch"
        );

        // Check start and end times
        assertEq(data.startTime, block.timestamp + DEFAULT_START_OFFSET, "Start time mismatch");
        assertEq(data.endTime, block.timestamp + DEFAULT_END_OFFSET, "End time mismatch");

        // Check start weights
        assertEq(data.startWeights.length, startWeights.length, "Start weights length mismatch");
        assertEq(data.startWeights[projectIdx], startWeights[projectIdx], "Project start weight mismatch");
        assertEq(data.startWeights[reserveIdx], startWeights[reserveIdx], "Reserve start weight mismatch");

        // Check end weights
        assertEq(data.endWeights.length, endWeights.length, "End weights length mismatch");
        assertEq(data.endWeights[projectIdx], endWeights[projectIdx], "Project end weight mismatch");
        assertEq(data.endWeights[reserveIdx], endWeights[reserveIdx], "Reserve end weight mismatch");
    }

    /*******************************************************************************
                                    Base Pool Hooks
    *******************************************************************************/

    function testOnSwapDisabled() public {
        // Create swap request params
        PoolSwapParams memory request = PoolSwapParams({
            kind: SwapKind.EXACT_IN,
            amountGivenScaled18: 1e18,
            balancesScaled18: vault.getCurrentLiveBalances(pool),
            indexIn: reserveIdx,
            indexOut: projectIdx,
            router: address(router),
            userData: bytes("")
        });

        // Before start time, swaps should be disabled
        vm.expectRevert(LBPool.SwapsDisabled.selector);
        vm.prank(address(vault));
        LBPool(pool).onSwap(request);

        // Warp to after end time
        vm.warp(block.timestamp + DEFAULT_END_OFFSET + 1);

        // After end time, swaps should also be disabled
        vm.expectRevert(LBPool.SwapsDisabled.selector);
        vm.prank(address(vault));
        LBPool(pool).onSwap(request);
    }

    function testOnSwapProjectTokenInNotAllowed() public {
        // Warp to when swaps are enabled
        vm.warp(block.timestamp + DEFAULT_START_OFFSET + 1);

        // Create swap request params - trying to swap project token for reserve token
        PoolSwapParams memory request = PoolSwapParams({
            kind: SwapKind.EXACT_IN,
            amountGivenScaled18: 1e18,
            balancesScaled18: vault.getCurrentLiveBalances(pool),
            indexIn: projectIdx, // Project token as input
            indexOut: reserveIdx, // Reserve token as output
            router: address(router),
            userData: bytes("")
        });

        // Should revert when trying to swap project token in
        vm.expectRevert(LBPool.SwapOfProjectTokenIn.selector);
        vm.prank(address(vault));
        LBPool(pool).onSwap(request);
    }

    function testOnSwapProjectTokenInAllowed() public {
        // Deploy a new pool with project token swaps enabled
        (address newPool, ) = _deployAndInitializeWithCustomWeights(
            startWeights[projectIdx],
            startWeights[reserveIdx],
            endWeights[projectIdx],
            endWeights[reserveIdx],
            uint32(block.timestamp + DEFAULT_START_OFFSET),
            uint32(block.timestamp + DEFAULT_END_OFFSET),
            true // Enable project token swaps in
        );

        // Warp to when swaps are enabled
        vm.warp(block.timestamp + DEFAULT_START_OFFSET + 1);

        // Create swap request params - swapping project token for reserve token
        PoolSwapParams memory request = PoolSwapParams({
            kind: SwapKind.EXACT_IN,
            amountGivenScaled18: 1e18,
            balancesScaled18: vault.getCurrentLiveBalances(newPool),
            indexIn: projectIdx,
            indexOut: reserveIdx,
            router: address(router),
            userData: bytes("")
        });

        // Mock vault call to onSwap
        vm.prank(address(vault));
        uint256 amountCalculated = LBPool(newPool).onSwap(request);

        // Verify amount calculated is non-zero
        assertGt(amountCalculated, 0, "Swap amount should be greater than zero");
    }

    function testOnSwap() public {
        // Warp to when swaps are enabled
        vm.warp(block.timestamp + DEFAULT_START_OFFSET + 1);

        // Create swap request params - swapping reserve token for project token
        PoolSwapParams memory request = PoolSwapParams({
            kind: SwapKind.EXACT_IN,
            amountGivenScaled18: 1e18,
            balancesScaled18: vault.getCurrentLiveBalances(pool),
            indexIn: reserveIdx,
            indexOut: projectIdx,
            router: address(router),
            userData: bytes("")
        });

        // Mock vault call to onSwap
        vm.prank(address(vault));
        uint256 amountCalculated = LBPool(pool).onSwap(request);

        // Verify amount calculated is non-zero
        assertGt(amountCalculated, 0, "Swap amount should be greater than zero");
    }

    function testAddingLiquidityNotAllowed() public {
        // Try to add liquidity to the pool.
        vm.expectRevert(LBPool.AddingLiquidityNotAllowed.selector);
        router.addLiquidityProportional(pool, [poolInitAmount, poolInitAmount].toMemoryArray(), 1e18, false, bytes(""));
    }

    function testDonationNotAllowed() public {
        // Try to donate to the pool.
        vm.expectRevert(LBPool.AddingLiquidityNotAllowed.selector);
        router.donate(pool, [poolInitAmount, poolInitAmount].toMemoryArray(), false, bytes(""));
    }
}
