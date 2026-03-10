// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPCommon.sol";
import "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPool.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { LBPCommon } from "../../contracts/lbp/LBPCommon.sol";
import { WeightedLBPTest } from "./utils/WeightedLBPTest.sol";

/**
 * @notice Additional edge case and security-focused tests for LBPool.
 * @dev Tests cover: timing edge cases, weight interpolation boundaries, sandwich attack scenarios.
 */
contract LBPoolEdgeCasesTest is WeightedLBPTest {
    using ArrayHelpers for *;
    using CastingHelpers for address[];
    using FixedPoint for uint256;

    function setUp() public virtual override {
        super.setUp();
    }

    function createPool() internal virtual override returns (address newPool, bytes memory poolArgs) {
        return
            _createLBPool(
                address(0), // Pool creator
                uint32(block.timestamp + DEFAULT_START_OFFSET),
                uint32(block.timestamp + DEFAULT_END_OFFSET),
                DEFAULT_PROJECT_TOKENS_SWAP_IN
            );
    }

    /***************************************************************************
                          TIMING EDGE CASES
     ***************************************************************************/

    /**
     * @notice Test swap at exact startTime boundary
     * @dev Swaps should be enabled at exactly startTime
     */
    function testSwapAtExactStartTime() public {
        uint32 startTime = uint32(block.timestamp + DEFAULT_START_OFFSET);

        // Warp to exactly startTime
        vm.warp(startTime);

        assertTrue(ILBPCommon(pool).isSwapEnabled(), "Swap should be enabled at exact startTime");

        // Verify weights are exactly at start weights at startTime.
        LBPoolDynamicData memory dataAtStart = ILBPool(pool).getLBPoolDynamicData();
        assertEq(
            dataAtStart.normalizedWeights[projectIdx],
            startWeights[projectIdx],
            "Weight should be exactly startWeight at startTime"
        );
        assertEq(
            dataAtStart.normalizedWeights[reserveIdx],
            startWeights[reserveIdx],
            "Weight should be exactly startWeight at startTime"
        );

        // Create swap request
        PoolSwapParams memory request = PoolSwapParams({
            kind: SwapKind.EXACT_IN,
            amountGivenScaled18: 1e18,
            balancesScaled18: vault.getCurrentLiveBalances(pool),
            indexIn: reserveIdx,
            indexOut: projectIdx,
            router: address(router),
            userData: bytes("")
        });

        // Should succeed
        vm.prank(address(vault));
        uint256 amountOut = IBasePool(pool).onSwap(request);
        assertGt(amountOut, 0, "Swap should succeed at exact startTime");
    }

    /**
     * @notice Test swap at exact endTime boundary
     * @dev Swaps should still be ENABLED at exactly endTime (condition is block.timestamp <= endTime)
     */
    function testSwapAtExactEndTime() public {
        // Pool was created with startTime = block.timestamp + DEFAULT_START_OFFSET
        // and endTime = block.timestamp + DEFAULT_END_OFFSET
        LBPoolImmutableData memory data = ILBPool(pool).getLBPoolImmutableData();
        uint256 endTime = data.endTime;

        // Warp to exactly endTime
        vm.warp(endTime);

        // At exactly endTime, swaps are STILL enabled (condition is timestamp <= endTime)
        assertTrue(ILBPCommon(pool).isSwapEnabled(), "Swap should be enabled at exact endTime");

        // Swaps should succeed at exactly endTime.
        PoolSwapParams memory requestAtEndTime = PoolSwapParams({
            kind: SwapKind.EXACT_IN,
            amountGivenScaled18: 1e18,
            balancesScaled18: vault.getCurrentLiveBalances(pool),
            indexIn: reserveIdx,
            indexOut: projectIdx,
            router: address(router),
            userData: bytes("")
        });

        vm.prank(address(vault));
        uint256 amountOutAtEndTime = IBasePool(pool).onSwap(requestAtEndTime);
        assertGt(amountOutAtEndTime, 0, "Swap should succeed at exact endTime");

        // Warp to 1 second after endTime
        vm.warp(endTime + 1);

        // Now swaps should be disabled
        assertFalse(ILBPCommon(pool).isSwapEnabled(), "Swap should be disabled after endTime");

        // Weights should stay clamped at end weights after the sale window.
        LBPoolDynamicData memory dataAfterEnd = ILBPool(pool).getLBPoolDynamicData();
        assertEq(
            dataAfterEnd.normalizedWeights[projectIdx],
            endWeights[projectIdx],
            "Weight should remain endWeight after endTime"
        );
        assertEq(
            dataAfterEnd.normalizedWeights[reserveIdx],
            endWeights[reserveIdx],
            "Weight should remain endWeight after endTime"
        );

        // Create swap request
        PoolSwapParams memory request = PoolSwapParams({
            kind: SwapKind.EXACT_IN,
            amountGivenScaled18: 1e18,
            balancesScaled18: vault.getCurrentLiveBalances(pool),
            indexIn: reserveIdx,
            indexOut: projectIdx,
            router: address(router),
            userData: bytes("")
        });

        // Should revert
        vm.prank(address(vault));
        vm.expectRevert(LBPCommon.SwapsDisabled.selector);
        IBasePool(pool).onSwap(request);
    }

    /***************************************************************************
                      WEIGHT INTERPOLATION EDGE CASES
     ***************************************************************************/

    /**
     * @notice Test weights still sum to 1 during interpolation at various times
     */
    function testWeightsSumToOneDuringInterpolation__Fuzz(uint256 rawTimeDelta) public {
        uint32 startTime = uint32(block.timestamp + DEFAULT_START_OFFSET);
        uint32 endTime = uint32(block.timestamp + DEFAULT_END_OFFSET);
        uint256 duration = endTime - startTime;

        // Random time within the sale period
        uint256 timeDelta = bound(rawTimeDelta, 0, duration);
        vm.warp(startTime + timeDelta);

        LBPoolDynamicData memory data = ILBPool(pool).getLBPoolDynamicData();

        uint256 weightSum = data.normalizedWeights[projectIdx] + data.normalizedWeights[reserveIdx];

        assertEq(weightSum, FixedPoint.ONE, "Weights should sum to 1 at all times");
    }

    /**
     * @notice Test weight monotonically changes during sale
     * @dev Project token weight should decrease monotonically (in typical LBP setup)
     */
    function testWeightMonotonicallyChanges() public {
        uint32 startTime = uint32(block.timestamp + DEFAULT_START_OFFSET);
        uint32 endTime = uint32(block.timestamp + DEFAULT_END_OFFSET);

        // Sample weights at 10 points throughout the sale
        uint256 previousProjectWeight = startWeights[projectIdx];
        uint256 numSamples = 10;
        uint256 duration = endTime - startTime;

        for (uint256 i = 1; i <= numSamples; i++) {
            vm.warp(startTime + (duration * i) / numSamples);

            LBPoolDynamicData memory data = ILBPool(pool).getLBPoolDynamicData();
            uint256 currentProjectWeight = data.normalizedWeights[projectIdx];

            // In standard LBP setup, project token weight decreases over time
            if (startWeights[projectIdx] > endWeights[projectIdx]) {
                assertLe(currentProjectWeight, previousProjectWeight, "Project weight should decrease monotonically");
            } else {
                assertGe(currentProjectWeight, previousProjectWeight, "Project weight should increase monotonically");
            }

            previousProjectWeight = currentProjectWeight;
        }
    }

    /***************************************************************************
                      SANDWICH ATTACK SIMULATION
     ***************************************************************************/

    /**
     * @notice Sandwich-like round trip on an unblocked LBP should not be profitable.
     * @dev This uses an unblocked pool so both legs are possible; rounding should favor the pool.
     */
    function testSandwichAttackAcrossWeightTransitionUnblockedNoProfit() public {
        // Create a new pool with project token swaps NOT blocked (for round-trip testing).
        uint256 currentTime = block.timestamp;
        uint32 startTime = uint32(currentTime + 1 hours);
        uint32 endTime = uint32(currentTime + 1 days);

        (address unblockPool, ) = _createLBPoolWithCustomWeights(
            address(0),
            startWeights[projectIdx],
            startWeights[reserveIdx],
            endWeights[projectIdx],
            endWeights[reserveIdx],
            startTime,
            endTime,
            false // Don't block project token swaps
        );

        // Initialize BEFORE startTime (required by LBP hooks).
        vm.startPrank(bob);
        _initPool(unblockPool, [poolInitAmount, poolInitAmount].toMemoryArray(), 0);
        vm.stopPrank();

        // Warp to just after startTime.
        vm.warp(startTime + 1);

        uint256[] memory initialBalances = vault.getCurrentLiveBalances(unblockPool);

        // Front-run: buy project tokens with reserve.
        uint256 attackAmount = 10e18;
        PoolSwapParams memory frontRunRequest = PoolSwapParams({
            kind: SwapKind.EXACT_IN,
            amountGivenScaled18: attackAmount,
            balancesScaled18: initialBalances,
            indexIn: reserveIdx,
            indexOut: projectIdx,
            router: address(router),
            userData: bytes("")
        });

        vm.prank(address(vault));
        uint256 projectTokensReceived = IBasePool(unblockPool).onSwap(frontRunRequest);

        // Time passes; weights change.
        vm.warp(block.timestamp + 100);

        // Update balances after front-run for the reverse swap.
        uint256[] memory balancesAfterFrontRun = new uint256[](2);
        balancesAfterFrontRun[reserveIdx] = initialBalances[reserveIdx] + attackAmount;
        balancesAfterFrontRun[projectIdx] = initialBalances[projectIdx] - projectTokensReceived;

        // Back-run: sell project tokens back into the pool.
        PoolSwapParams memory backRunRequest = PoolSwapParams({
            kind: SwapKind.EXACT_IN,
            amountGivenScaled18: projectTokensReceived,
            balancesScaled18: balancesAfterFrontRun,
            indexIn: projectIdx,
            indexOut: reserveIdx,
            router: address(router),
            userData: bytes("")
        });

        vm.prank(address(vault));
        uint256 reserveTokensReceived = IBasePool(unblockPool).onSwap(backRunRequest);

        assertLe(reserveTokensReceived, attackAmount, "Attacker should not profit from sandwich-like round trip");
    }

    /**
     * @notice Test that blocking project token swaps in prevents buying
     */
    function testProjectTokenSwapBlockingPreventsAttack() public {
        // Pool is created with DEFAULT_PROJECT_TOKENS_SWAP_IN = true (blocked)
        assertTrue(ILBPCommon(pool).isProjectTokenSwapInBlocked(), "Project token swap in should be blocked");

        uint32 startTime = uint32(block.timestamp + DEFAULT_START_OFFSET);
        vm.warp(startTime + 1);

        // Note: the EXACT_IN revert path is already covered in `LBPool.t.sol`.
        // Unique coverage here: the EXACT_OUT path must also be blocked.
        PoolSwapParams memory exactOutRequest = PoolSwapParams({
            kind: SwapKind.EXACT_OUT,
            amountGivenScaled18: 1e18, // Want exactly 1e18 reserve token out
            balancesScaled18: vault.getCurrentLiveBalances(pool),
            indexIn: projectIdx,
            indexOut: reserveIdx,
            router: address(router),
            userData: bytes("")
        });

        vm.prank(address(vault));
        vm.expectRevert(LBPCommon.SwapOfProjectTokenIn.selector);
        IBasePool(pool).onSwap(exactOutRequest);
    }

    /***************************************************************************
                      VERY SHORT / LONG SALE PERIODS
     ***************************************************************************/

    /**
     * @notice Test LBP with very short sale period (1 second)
     */
    function testVeryShortSalePeriod() public {
        // Record current timestamp before creating pool
        uint256 currentTime = block.timestamp;
        uint32 shortStartTime = uint32(currentTime + 1 hours);
        uint32 shortEndTime = shortStartTime + 1; // Only 1 second

        (address shortPool, ) = _createLBPoolWithCustomWeights(
            address(0),
            startWeights[projectIdx],
            startWeights[reserveIdx],
            endWeights[projectIdx],
            endWeights[reserveIdx],
            shortStartTime,
            shortEndTime,
            false
        );

        // Initialize the short pool BEFORE startTime (this is required by LBP hooks)
        // Use startPrank/stopPrank to ensure all nested calls see bob as sender
        vm.startPrank(bob);
        _initPool(shortPool, [poolInitAmount, poolInitAmount].toMemoryArray(), 0);
        vm.stopPrank();

        // Now warp to start and verify
        vm.warp(shortStartTime);
        assertTrue(ILBPCommon(shortPool).isSwapEnabled(), "Swap should be enabled");

        // Check weights are still at start (no time has passed in the 1-second window)
        LBPoolDynamicData memory dataAtStart = ILBPool(shortPool).getLBPoolDynamicData();
        assertEq(dataAtStart.normalizedWeights[projectIdx], startWeights[projectIdx], "Weight should be at start");

        // Warp to end (at exactly endTime, swaps are still enabled due to <= condition)
        vm.warp(shortEndTime);
        assertTrue(ILBPCommon(shortPool).isSwapEnabled(), "Swap should still be enabled at exact endTime");

        // Warp to 1 second after end
        vm.warp(shortEndTime + 1);
        assertFalse(ILBPCommon(shortPool).isSwapEnabled(), "Swap should be disabled after endTime");

        // Check weights are at end (they stay at end weights after endTime)
        LBPoolDynamicData memory dataAtEnd = ILBPool(shortPool).getLBPoolDynamicData();
        assertEq(dataAtEnd.normalizedWeights[projectIdx], endWeights[projectIdx], "Weight should be at end after sale");
    }

    /**
     * @notice Test LBP with very long sale period (1 year)
     */
    function testVeryLongSalePeriod() public {
        // Record current timestamp before creating pool
        uint256 currentTime = block.timestamp;
        uint32 longStartTime = uint32(currentTime + 1 hours);
        uint32 longEndTime = longStartTime + 365 days; // 1 year

        (address longPool, ) = _createLBPoolWithCustomWeights(
            address(0),
            startWeights[projectIdx],
            startWeights[reserveIdx],
            endWeights[projectIdx],
            endWeights[reserveIdx],
            longStartTime,
            longEndTime,
            false
        );

        // Initialize BEFORE startTime (this is required by LBP hooks)
        vm.startPrank(bob);
        _initPool(longPool, [poolInitAmount, poolInitAmount].toMemoryArray(), 0);
        vm.stopPrank();

        // Now warp to 6 months after startTime (halfway through sale)
        vm.warp(uint256(longStartTime) + 182.5 days);

        LBPoolDynamicData memory dataAtHalfway = ILBPool(longPool).getLBPoolDynamicData();

        // Weights should be approximately halfway between start and end
        uint256 expectedProjectWeight = (startWeights[projectIdx] + endWeights[projectIdx]) / 2;

        // Allow 1% tolerance for rounding
        assertApproxEqRel(
            dataAtHalfway.normalizedWeights[projectIdx],
            expectedProjectWeight,
            1e16,
            "Weight should be approximately halfway"
        );
    }

    /***************************************************************************
                      EXACT SWAP SCENARIOS
     ***************************************************************************/

    /**
     * @notice Test ExactOut swap during LBP
     */
    function testExactOutSwap() public {
        uint32 startTime = uint32(block.timestamp + DEFAULT_START_OFFSET);
        vm.warp(startTime + 1);

        uint256[] memory balances = vault.getCurrentLiveBalances(pool);
        uint256 exactOutSmall = balances[projectIdx] / 1000;
        if (exactOutSmall == 0) exactOutSmall = 1;
        uint256 exactOutLarge = exactOutSmall * 2;
        if (exactOutLarge >= balances[projectIdx]) exactOutLarge = balances[projectIdx] - 1;

        PoolSwapParams memory requestSmall = PoolSwapParams({
            kind: SwapKind.EXACT_OUT,
            amountGivenScaled18: exactOutSmall,
            balancesScaled18: balances,
            indexIn: reserveIdx,
            indexOut: projectIdx,
            router: address(router),
            userData: bytes("")
        });

        vm.prank(address(vault));
        uint256 amountInSmall = IBasePool(pool).onSwap(requestSmall);
        assertGt(amountInSmall, 0, "Should require some input for exact output");

        PoolSwapParams memory requestLarge = PoolSwapParams({
            kind: SwapKind.EXACT_OUT,
            amountGivenScaled18: exactOutLarge,
            balancesScaled18: balances,
            indexIn: reserveIdx,
            indexOut: projectIdx,
            router: address(router),
            userData: bytes("")
        });

        vm.prank(address(vault));
        uint256 amountInLarge = IBasePool(pool).onSwap(requestLarge);

        assertGe(amountInLarge, amountInSmall, "Larger exactOut should require >= input");
    }

    /**
     * @notice Test that swap amounts are affected by current weights
     */
    function testSwapAmountChangesWithWeights() public {
        uint32 startTime = uint32(block.timestamp + DEFAULT_START_OFFSET);
        uint32 endTime = uint32(block.timestamp + DEFAULT_END_OFFSET);

        // Swap at start
        vm.warp(startTime);
        uint256[] memory balancesAtStart = vault.getCurrentLiveBalances(pool);

        PoolSwapParams memory requestAtStart = PoolSwapParams({
            kind: SwapKind.EXACT_IN,
            amountGivenScaled18: 1e18,
            balancesScaled18: balancesAtStart,
            indexIn: reserveIdx,
            indexOut: projectIdx,
            router: address(router),
            userData: bytes("")
        });

        vm.prank(address(vault));
        uint256 amountOutAtStart = IBasePool(pool).onSwap(requestAtStart);

        // Swap near end (use same balances to isolate weight effect)
        vm.warp(endTime - 1); // Just before end to keep swaps enabled

        PoolSwapParams memory requestAtEnd = PoolSwapParams({
            kind: SwapKind.EXACT_IN,
            amountGivenScaled18: 1e18,
            balancesScaled18: balancesAtStart, // Same balances
            indexIn: reserveIdx,
            indexOut: projectIdx,
            router: address(router),
            userData: bytes("")
        });

        vm.prank(address(vault));
        uint256 amountOutAtEnd = IBasePool(pool).onSwap(requestAtEnd);

        // Directional check:
        // In standard LBP setup (project weight decreases), buying project tokens with reserve gets cheaper over time,
        // so the same reserve input should yield MORE project tokens later.
        if (startWeights[projectIdx] > endWeights[projectIdx]) {
            assertGt(amountOutAtEnd, amountOutAtStart, "Buying project token should get cheaper over time");
        } else {
            // If configured with increasing project weight, buying should get more expensive.
            assertLt(amountOutAtEnd, amountOutAtStart, "Buying project token should get more expensive over time");
        }
    }
}
