// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IStablePool, AmplificationState } from "@balancer-labs/v3-interfaces/contracts/pool-stable/IStablePool.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";
import { StableMath } from "@balancer-labs/v3-solidity-utils/contracts/math/StableMath.sol";

import { StablePoolContractsDeployer } from "./utils/StablePoolContractsDeployer.sol";
import { StablePoolFactory } from "../../contracts/StablePoolFactory.sol";
import { StablePool } from "../../contracts/StablePool.sol";

/**
 * @title AmplificationInterpolationTest
 * @notice Foundry fuzz tests for amplification parameter updates.
 * @dev Tests cover:
 *   - Amp value at exact start/end times
 *   - Amp monotonically changes during update
 *   - Rate limit edge cases
 *   - Multiple concurrent update attempts
 *   - Interpolation accuracy
 */
contract AmplificationInterpolationTest is StablePoolContractsDeployer, BaseVaultTest {
    uint256 internal constant DEFAULT_AMP = 200;
    uint256 internal constant MIN_AMP = StableMath.MIN_AMP;
    uint256 internal constant MAX_AMP = StableMath.MAX_AMP;
    uint256 internal constant AMP_PRECISION = StableMath.AMP_PRECISION;
    uint256 internal constant MIN_UPDATE_TIME = 1 days;
    uint256 internal constant MAX_AMP_UPDATE_DAILY_RATE = 2;
    uint256 internal constant DEFAULT_SWAP_FEE = 1e12;
    string internal constant POOL_VERSION = "Pool v1";

    StablePoolFactory internal stableFactory;
    address internal stablePool;
    uint256 internal poolCreationNonce;

    function setUp() public override {
        super.setUp();
        stableFactory = deployStablePoolFactory(IVault(address(vault)), 365 days, "Factory v1", POOL_VERSION);
        stablePool = _createAndInitStablePool(DEFAULT_AMP, 1e20, 1e20);
    }

    /***************************************************************************
                          Revert Branch / Boundary Coverage
     ***************************************************************************/

    function testConstructorRevertsWhenAmpTooLow() public {
        StablePool.NewPoolParams memory params = StablePool.NewPoolParams({
            name: "Stable Coverage",
            symbol: "COV",
            amplificationParameter: MIN_AMP - 1,
            version: POOL_VERSION
        });

        vm.expectRevert(StablePool.AmplificationFactorTooLow.selector);
        new StablePool(params, IVault(address(vault)));
    }

    function testConstructorRevertsWhenAmpTooHigh() public {
        StablePool.NewPoolParams memory params = StablePool.NewPoolParams({
            name: "Stable Coverage",
            symbol: "COV",
            amplificationParameter: MAX_AMP + 1,
            version: POOL_VERSION
        });

        vm.expectRevert(StablePool.AmplificationFactorTooHigh.selector);
        new StablePool(params, IVault(address(vault)));
    }

    function testStartAmplificationUpdateRevertsWhenEndAmpTooLow() public {
        vm.prank(alice);
        vm.expectRevert(StablePool.AmplificationFactorTooLow.selector);
        IStablePool(stablePool).startAmplificationParameterUpdate(MIN_AMP - 1, block.timestamp + 10 days);
    }

    function testStartAmplificationUpdateRevertsWhenEndAmpTooHigh() public {
        vm.prank(alice);
        vm.expectRevert(StablePool.AmplificationFactorTooHigh.selector);
        IStablePool(stablePool).startAmplificationParameterUpdate(MAX_AMP + 1, block.timestamp + 10 days);
    }

    function testStartAmplificationUpdateRevertsWhenDurationTooShort() public {
        vm.prank(alice);
        vm.expectRevert(StablePool.AmpUpdateDurationTooShort.selector);
        IStablePool(stablePool).startAmplificationParameterUpdate(
            DEFAULT_AMP * 2,
            block.timestamp + MIN_UPDATE_TIME - 1
        );
    }

    function testStartAmplificationUpdateRevertsWhenAlreadyStarted() public {
        uint256 endTime = block.timestamp + 10 days;

        vm.startPrank(alice);
        IStablePool(stablePool).startAmplificationParameterUpdate(DEFAULT_AMP * 2, endTime);
        vm.expectRevert(StablePool.AmpUpdateAlreadyStarted.selector);
        IStablePool(stablePool).startAmplificationParameterUpdate(DEFAULT_AMP * 3, endTime + 1 days);
        vm.stopPrank();
    }

    function testStopAmplificationUpdateRevertsWhenNotStarted() public {
        vm.prank(alice);
        vm.expectRevert(StablePool.AmpUpdateNotStarted.selector);
        IStablePool(stablePool).stopAmplificationParameterUpdate();
    }

    /***************************************************************************
                            Exact Timing Tests
     ***************************************************************************/

    /**
     * @notice Off-by-one safety around endTime.
     * @dev - 1 second before: still updating and strictly between start/end (for increase).
     *      - at endTime and after: update is finished and amp is exactly the end value.
     */
    function testAmpAroundEndTimeBoundaries() public {
        uint256 startAmp = DEFAULT_AMP;
        uint256 endAmp = DEFAULT_AMP * 2;
        uint256 duration = 10 days;
        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + duration;

        _startAmpUpdate(endAmp, endTime);

        // Warp to 1 second before end
        vm.warp(endTime - 1);

        (uint256 currentAmp, bool isUpdating, ) = IStablePool(stablePool).getAmplificationParameter();
        assertTrue(isUpdating, "Should still be updating");
        assertLt(currentAmp, endAmp * AMP_PRECISION, "Amp should be less than end value");
        assertGt(currentAmp, startAmp * AMP_PRECISION, "Amp should be greater than start value");

        // Warp to exact end time
        vm.warp(endTime);
        (uint256 ampAtEnd, bool updatingAtEnd, ) = IStablePool(stablePool).getAmplificationParameter();
        assertFalse(updatingAtEnd, "Should not be updating at end time");
        assertEq(ampAtEnd, endAmp * AMP_PRECISION, "Amp should be at end value at end time");

        // Warp to 1 second after end
        vm.warp(endTime + 1);
        (uint256 ampAfterEnd, bool updatingAfterEnd, ) = IStablePool(stablePool).getAmplificationParameter();
        assertFalse(updatingAfterEnd, "Should not be updating after end time");
        assertEq(ampAfterEnd, endAmp * AMP_PRECISION, "Amp should remain at end value after end time");
    }

    /***************************************************************************
                          MONOTONICITY TESTS
     ***************************************************************************/

    /**
     * @notice Amp must be monotone non-decreasing during an upward update.
     * @dev Uses two arbitrary timestamps (not just adjacent seconds) to avoid a vacuous "stuck rounding step" test.
     */
    function testAmpMonotoneNonDecreasingDuringIncrease__Fuzz(uint256 rawT1, uint256 rawT2) public {
        uint256 endAmp = DEFAULT_AMP * 2;
        uint256 duration = 10 days;
        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + duration;

        _startAmpUpdate(endAmp, endTime);

        uint256 t1 = bound(rawT1, 1, duration - 1);
        uint256 t2 = bound(rawT2, 1, duration - 1);
        if (t1 > t2) (t1, t2) = (t2, t1);

        vm.warp(startTime + t1);
        (uint256 amp1, bool updating1, ) = IStablePool(stablePool).getAmplificationParameter();
        assertTrue(updating1, "Should be updating before endTime");

        vm.warp(startTime + t2);
        (uint256 amp2, bool updating2, ) = IStablePool(stablePool).getAmplificationParameter();
        assertTrue(updating2, "Should be updating before endTime");

        assertGe(amp2, amp1, "Amp should monotonically non-decrease during increase");
        // Strengthen beyond "vacuous monotonicity": with enough time gap, the value must move.
        // For DEFAULT_AMP=200 -> 400 over 10 days, the slope is ~0.23 units/second (in scaled units),
        // so a 10-second gap should always advance the integer value by at least 1.
        if (t2 >= t1 + 10) {
            assertGt(amp2, amp1, "Amp should strictly increase with sufficient time gap");
        }
    }

    /**
     * @notice Amp must be monotone non-increasing during a downward update.
     * @dev Uses a fresh pool initialized at the higher amp (avoids the extra “increase first” dance).
     */
    function testAmpMonotoneNonIncreasingDuringDecrease__Fuzz(uint256 rawT1, uint256 rawT2) public {
        uint256 startAmp = DEFAULT_AMP * 2;
        uint256 endAmp = DEFAULT_AMP;
        uint256 duration = 10 days;
        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + duration;

        stablePool = _createAndInitStablePool(startAmp, 1e20, 1e20);
        _startAmpUpdate(endAmp, endTime);

        uint256 t1 = bound(rawT1, 1, duration - 1);
        uint256 t2 = bound(rawT2, 1, duration - 1);
        if (t1 > t2) (t1, t2) = (t2, t1);

        vm.warp(startTime + t1);
        (uint256 amp1, bool updating1, ) = IStablePool(stablePool).getAmplificationParameter();
        assertTrue(updating1, "Should be updating before endTime");

        vm.warp(startTime + t2);
        (uint256 amp2, bool updating2, ) = IStablePool(stablePool).getAmplificationParameter();
        assertTrue(updating2, "Should be updating before endTime");

        assertLe(amp2, amp1, "Amp should monotonically non-increase during decrease");
        // Same "non-vacuous" strengthening: with enough time gap, the value must move.
        if (t2 >= t1 + 10) {
            assertLt(amp2, amp1, "Amp should strictly decrease with sufficient time gap");
        }
    }

    /***************************************************************************
                                 Rate Limit Tests
     ***************************************************************************/

    /// @notice Test update at exactly maximum allowed rate succeeds.
    function testUpdateAtMaxRate() public {
        uint256 startAmp = DEFAULT_AMP;
        // Double in exactly 1 day (max rate)
        uint256 endAmp = startAmp * MAX_AMP_UPDATE_DAILY_RATE;
        uint256 duration = MIN_UPDATE_TIME;
        uint256 endTime = block.timestamp + duration;

        // Should succeed at max rate
        _startAmpUpdate(endAmp, endTime);

        (uint256 currentAmp, bool isUpdating, ) = IStablePool(stablePool).getAmplificationParameter();
        assertTrue(isUpdating, "Update should have started");
        assertEq(currentAmp, startAmp * AMP_PRECISION, "Amp should still be start value right after start");

        (AmplificationState memory state, uint256 precision) = IStablePool(stablePool).getAmplificationState();
        assertEq(precision, AMP_PRECISION, "Unexpected amp precision");
        assertEq(state.startValue, startAmp * precision, "Wrong startValue");
        assertEq(state.endValue, endAmp * precision, "Wrong endValue");
        assertEq(state.endTime, endTime, "Wrong endTime");
    }

    /// @notice Test halving rate (decrease) at max rate.
    function testHalvingAtMaxRate() public {
        // Use a fresh pool initialized at 400 so we can test the downward rate limit directly.
        stablePool = _createAndInitStablePool(400, 1e20, 1e20);

        uint256 currentAmp = 400;
        uint256 endAmp = currentAmp / MAX_AMP_UPDATE_DAILY_RATE; // 200
        uint256 duration = MIN_UPDATE_TIME;
        uint256 endTime = block.timestamp + duration;

        // Should succeed at max rate
        _startAmpUpdate(endAmp, endTime);

        (, bool isUpdating, ) = IStablePool(stablePool).getAmplificationParameter();
        assertTrue(isUpdating, "Update should have started");
    }

    /**
     * @notice Test that larger amp changes require proportionally longer durations.
     * @dev The pool enforces a linear "dailyRate" cap, roughly:
     *   ceil((end/start) / (duration / 1 day)) <= 2
     * So a single-shot 8x change needs at least 4 days (ceil(8/4)=2).
     */
    function testLargeChangeRequiresLongerDuration() public {
        uint256 startAmp = DEFAULT_AMP; // 200
        uint256 endAmp = startAmp * 8; // 8x

        // 8x over 2 days should exceed a 2x/day cap (ceil(8/2)=4).
        vm.expectRevert(StablePool.AmpUpdateRateTooFast.selector);
        _startAmpUpdate(endAmp, block.timestamp + 2 days);

        // 8x over 3 days is still too fast under the linear cap (ceil(8/3)=3).
        vm.expectRevert(StablePool.AmpUpdateRateTooFast.selector);
        _startAmpUpdate(endAmp, block.timestamp + 3 days);

        // 8x over 4 days is the minimum that should succeed (ceil(8/4)=2).
        _startAmpUpdate(endAmp, block.timestamp + 4 days);
        (, bool isUpdating, ) = IStablePool(stablePool).getAmplificationParameter();
        assertTrue(isUpdating, "Update should have started");
    }

    /**
     * @notice Even though each individual update is capped at 2x/day, multiple sequential updates can compound.
     * @dev This is explicitly called out in `StablePool.sol` and is important to keep as a documented,
     * tested behavior. If this ever changes, it is a governance/process/security-relevant behavior change.
     */
    function testSequentialDoublingReaches8xOver3Days() public {
        uint256 startAmp = DEFAULT_AMP; // 200
        uint256 a1 = startAmp * 2; // 400
        uint256 a2 = startAmp * 4; // 800
        uint256 a3 = startAmp * 8; // 1600

        uint256 t0 = block.timestamp;

        // Day 1: 200 -> 400 (allowed).
        _startAmpUpdate(a1, t0 + 1 days);
        vm.warp(t0 + 1 days);
        (uint256 amp1, bool updating1, ) = IStablePool(stablePool).getAmplificationParameter();
        assertFalse(updating1, "Update should have completed at day 1");
        assertEq(amp1, a1 * AMP_PRECISION, "Amp should be 2x after day 1");

        // Day 2: 400 -> 800 (allowed).
        _startAmpUpdate(a2, t0 + 2 days);
        vm.warp(t0 + 2 days);
        (uint256 amp2, bool updating2, ) = IStablePool(stablePool).getAmplificationParameter();
        assertFalse(updating2, "Update should have completed at day 2");
        assertEq(amp2, a2 * AMP_PRECISION, "Amp should be 4x after day 2");

        // Day 3: 800 -> 1600 (allowed).
        _startAmpUpdate(a3, t0 + 3 days);
        vm.warp(t0 + 3 days);
        (uint256 amp3, bool updating3, ) = IStablePool(stablePool).getAmplificationParameter();
        assertFalse(updating3, "Update should have completed at day 3");
        assertEq(amp3, a3 * AMP_PRECISION, "Amp should be 8x after day 3");
    }

    /// @notice Test stop then restart works.
    function testStopThenRestart() public {
        uint256 endAmp1 = DEFAULT_AMP * 2;
        uint256 duration = 10 days;
        uint256 startTime = block.timestamp;
        uint256 endTime1 = startTime + duration;

        _startAmpUpdate(endAmp1, endTime1);

        // Warp to middle (update is still in progress)
        // Pick a timestamp that is very likely to yield a non-multiple-of-precision amp value, so we exercise
        // the conservative (round-up) daily-rate check on restart.
        uint256 stopTime = startTime + duration / 2 + 50;
        vm.warp(stopTime);

        (, bool isUpdating, ) = IStablePool(stablePool).getAmplificationParameter();
        assertTrue(isUpdating, "Should be updating at midpoint");

        // Stop update
        _stopAmpUpdate();

        uint256 stoppedAmp;
        (stoppedAmp, isUpdating, ) = IStablePool(stablePool).getAmplificationParameter();
        assertFalse(isUpdating, "Should not be updating after stop");
        assertTrue(stoppedAmp > 0, "Stopped amp should be non-zero");

        // After stopping, amp should be time-invariant.
        vm.warp(stopTime + 5 days);
        (uint256 ampLater, bool stillUpdating, ) = IStablePool(stablePool).getAmplificationParameter();
        assertFalse(stillUpdating, "Should remain not updating after stop");
        assertEq(ampLater, stoppedAmp, "Amp should be frozen after stop");

        // Start new update: derive the *maximal* raw end amp that should be allowed under the 2x/day cap,
        // even when the current (scaled) amp is not divisible by AMP_PRECISION.
        uint256 maxAllowedEndAmpRaw = (stoppedAmp * MAX_AMP_UPDATE_DAILY_RATE) / AMP_PRECISION;
        uint256 endTime2 = block.timestamp + MIN_UPDATE_TIME;

        _startAmpUpdate(maxAllowedEndAmpRaw, endTime2);

        (uint256 ampAfterRestart, bool isUpdatingAfterRestart, ) = IStablePool(stablePool).getAmplificationParameter();
        assertTrue(isUpdatingAfterRestart, "New update should have started");
        assertEq(ampAfterRestart, stoppedAmp, "Restart should begin from the stopped amp value");

        (AmplificationState memory state, uint256 precision) = IStablePool(stablePool).getAmplificationState();
        assertEq(state.startValue, stoppedAmp, "Restart startValue should equal stopped amp");
        assertEq(state.endValue, maxAllowedEndAmpRaw * precision, "Restart endValue mismatch");

        // Stop the restarted update, and verify that exceeding the tight 2x/day bound by the smallest unit reverts.
        // This specifically exercises the daily-rate computation when the current (scaled) amp isn't divisible by AMP_PRECISION.
        _stopAmpUpdate();
        vm.expectRevert(StablePool.AmpUpdateRateTooFast.selector);
        _startAmpUpdate(maxAllowedEndAmpRaw + 1, block.timestamp + MIN_UPDATE_TIME);
    }

    /***************************************************************************
                                Boundary Value Tests
     ***************************************************************************/

    /// @notice Test update to minimum amp.
    function testUpdateToMinAmp() public {
        // Need to create pool with higher amp first
        stablePool = _createAndInitStablePool(10, 1e20, 1e20);

        uint256 endAmp = MIN_AMP;
        uint256 duration = 10 days;
        uint256 endTime = block.timestamp + duration;

        _startAmpUpdate(endAmp, endTime);

        vm.warp(endTime + 1);

        (uint256 finalAmp, , ) = IStablePool(stablePool).getAmplificationParameter();
        assertEq(finalAmp, MIN_AMP * AMP_PRECISION, "Should reach min amp");
    }

    /***************************************************************************
                          Interpolation Accuracy Tests
     ***************************************************************************/

    /// @notice Test linear interpolation accuracy at various points.
    function testInterpolationAccuracy__Fuzz(uint256 rawPercentage) public {
        // Include endpoints; this test subsumes separate "exact start/end" checks for interpolation math.
        uint256 percentage = bound(rawPercentage, 0, 100); // 0-100%

        uint256 startAmp = DEFAULT_AMP;
        uint256 endAmp = DEFAULT_AMP * 2;
        uint256 duration = 10 days;
        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + duration;

        _startAmpUpdate(endAmp, endTime);

        // Warp to percentage of duration
        uint256 elapsed = (duration * percentage) / 100;
        vm.warp(startTime + elapsed);

        (uint256 currentAmp, bool isUpdating, ) = IStablePool(stablePool).getAmplificationParameter();

        // Calculate expected amp
        uint256 expectedAmp = startAmp *
            AMP_PRECISION +
            ((endAmp * AMP_PRECISION - startAmp * AMP_PRECISION) * elapsed) /
            duration;

        // Interpolation should match exactly (or be off by at most 1 due to integer division edge cases).
        assertApproxEqAbs(currentAmp, expectedAmp, 1, "Interpolation should be accurate");
        if (elapsed < duration) {
            assertTrue(isUpdating, "Should be updating before endTime");
        } else {
            assertFalse(isUpdating, "Should not be updating at endTime");
        }
    }

    /**
     * @notice Integration property test.
     * @dev As amp increases over time, a fixed ExactIn swap on a fresh pool should not yield *less* output at a later
     * timestamp (i.e., slippage should not worsen).
     */
    function testSwapOutputMonotoneInTimeDuringIncreasingAmp__Fuzz(uint256 rawT1, uint256 rawT2) public {
        uint256 startAmp = DEFAULT_AMP;
        uint256 endAmp = DEFAULT_AMP * 2;
        uint256 duration = 10 days;
        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + duration;

        // Use two fresh pools so pool state (post-swap balances) doesn't confound the comparison.
        address poolEarly = _createAndInitStablePool(startAmp, 1e20, 1e20);
        address poolLate = _createAndInitStablePool(startAmp, 1e20, 1e20);

        vm.startPrank(alice);
        IStablePool(poolEarly).startAmplificationParameterUpdate(endAmp, endTime);
        IStablePool(poolLate).startAmplificationParameterUpdate(endAmp, endTime);
        vm.stopPrank();

        IERC20[] memory tokens = _getDefaultTokens();
        uint256 swapAmount = 1e18;

        uint256 t1 = bound(rawT1, 0, duration);
        uint256 t2 = bound(rawT2, 0, duration);
        if (t1 > t2) (t1, t2) = (t2, t1);

        // Swap at earlier time
        vm.warp(startTime + t1);
        vm.prank(alice);
        uint256 amountOutEarly = router.swapSingleTokenExactIn(
            poolEarly,
            tokens[0],
            tokens[1],
            swapAmount,
            0,
            type(uint256).max,
            false,
            bytes("")
        );

        // Swap at later time
        vm.warp(startTime + t2);
        vm.prank(alice);
        uint256 amountOutLate = router.swapSingleTokenExactIn(
            poolLate,
            tokens[0],
            tokens[1],
            swapAmount,
            0,
            type(uint256).max,
            false,
            bytes("")
        );

        // Allow a 1-wei tolerance for integer-rounding artifacts.
        assertGe(amountOutLate + 1, amountOutEarly, "Swap output should not decrease as amp increases over time");
    }

    /***************************************************************************
                                    Helper Functions
     ***************************************************************************/

    function _createAndInitStablePool(
        uint256 amp,
        uint256 balance0,
        uint256 balance1
    ) internal returns (address newPool) {
        IERC20[] memory tokens = _getDefaultTokens();

        PoolRoleAccounts memory roleAccounts;
        roleAccounts.swapFeeManager = alice;

        newPool = stableFactory.create(
            "Stable Pool",
            "STABLE",
            vault.buildTokenConfig(tokens),
            amp,
            roleAccounts,
            DEFAULT_SWAP_FEE,
            address(0),
            false,
            false,
            bytes32(poolCreationNonce++)
        );

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = balance0;
        amounts[1] = balance1;

        vm.prank(lp);
        router.initialize(newPool, tokens, amounts, 0, false, bytes(""));
    }

    function _startAmpUpdate(uint256 endAmp, uint256 endTime) internal {
        vm.prank(alice);
        IStablePool(stablePool).startAmplificationParameterUpdate(endAmp, endTime);
    }

    function _stopAmpUpdate() internal {
        vm.prank(alice);
        IStablePool(stablePool).stopAmplificationParameterUpdate();
    }

    function _assertAmpStateEq(AmplificationState memory a, AmplificationState memory b) internal pure {
        assertEq(a.startValue, b.startValue, "AmpState startValue changed unexpectedly");
        assertEq(a.endValue, b.endValue, "AmpState endValue changed unexpectedly");
        assertEq(a.startTime, b.startTime, "AmpState startTime changed unexpectedly");
        assertEq(a.endTime, b.endTime, "AmpState endTime changed unexpectedly");
    }

    function _getDefaultTokens() internal view returns (IERC20[] memory tokens) {
        tokens = new IERC20[](2);
        tokens[0] = dai;
        tokens[1] = usdc;
        tokens = InputHelpers.sortTokens(tokens);
    }
}
