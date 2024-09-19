// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import "../../contracts/test/GradualValueChangeMock.sol";

contract GradualValueChangeTest is Test {
    uint256 private constant FP_ONE = 1e18;

    GradualValueChangeMock private mock;

    function setUp() public {
        mock = new GradualValueChangeMock();
    }

    function testGetInterpolatedValue() public {
        uint256 startValue = 100e18;
        uint256 endValue = 200e18;
        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + 100;
        uint256 steps = 100;

        for (uint256 i = 0; i <= steps; i++) {
            uint256 currentTime = startTime + ((i * (endTime - startTime)) / steps);
            vm.warp(currentTime);
            uint256 expectedValue = startValue + ((i * (endValue - startValue)) / steps);
            uint256 actualValue = mock.getInterpolatedValue(startValue, endValue, startTime, endTime);
            assertEq(actualValue, expectedValue, "Interpolated value should match expected");
        }
    }

    function testResolveStartTime() public {
        uint256 currentTime = 1000000;
        uint256 futureTime = currentTime + 100;

        vm.warp(currentTime);
        assertEq(mock.resolveStartTime(futureTime, futureTime + 100), futureTime, "Should return future start time");
        assertEq(
            mock.resolveStartTime(currentTime - 100, futureTime),
            currentTime,
            "Should return current time for past start time"
        );

        vm.expectRevert(GradualValueChange.GradualUpdateTimeTravel.selector);
        mock.resolveStartTime(futureTime + 200, futureTime + 100);
    }

    function testInterpolateValue() public view {
        uint256 startValue = 100e18;
        uint256 endValue = 200e18;
        uint256 steps = 100;

        for (uint256 i = 0; i <= steps; i++) {
            uint256 pctProgress = (i * FP_ONE) / steps;
            uint256 expectedValue = startValue + ((i * (endValue - startValue)) / steps);
            uint256 actualValue = mock.interpolateValue(startValue, endValue, pctProgress);
            assertEq(actualValue, expectedValue, "Interpolated value should match expected");
        }

        // Test decreasing value
        startValue = 200e18;
        endValue = 100e18;

        for (uint256 i = 0; i <= steps; i++) {
            uint256 pctProgress = (i * FP_ONE) / steps;
            uint256 expectedValue = startValue - ((i * (startValue - endValue)) / steps);
            uint256 actualValue = mock.interpolateValue(startValue, endValue, pctProgress);
            assertEq(actualValue, expectedValue, "Interpolated value should match expected for decreasing value");
        }
    }

    function testCalculateValueChangeProgress() public {
        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + 100;
        uint256 steps = 100;

        for (uint256 i = 0; i <= steps; i++) {
            uint256 currentTime = startTime + ((i * (endTime - startTime)) / steps);
            vm.warp(currentTime);
            uint256 expectedProgress = (i * FP_ONE) / steps;
            uint256 actualProgress = mock.calculateValueChangeProgress(startTime, endTime);
            // Use a very tight tolerance for progress calculation
            assertApproxEqAbs(actualProgress, expectedProgress, 1, "Progress should be very close to expected");
        }

        vm.warp(endTime + 50);
        assertEq(mock.calculateValueChangeProgress(startTime, endTime), FP_ONE, "Should be complete after end time");
    }

    function testEdgeCases() public {
        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + 100;

        uint256 startValue = 100e18;
        uint256 endValue = 200e18;

        for (uint256 i = 0; i <= 100; i++) {
            vm.warp(startTime + i);
            assertEq(
                mock.getInterpolatedValue(startValue, startValue, startTime, endTime),
                startValue,
                "Should always return the same value"
            );
        }

        // Test before start time
        vm.warp(startTime - 1);
        assertEq(
            mock.getInterpolatedValue(startValue, endValue, startTime, startTime),
            startValue,
            "Should return start value before start time for zero duration"
        );

        // Test at start time
        vm.warp(startTime);
        assertEq(
            mock.getInterpolatedValue(startValue, endValue, startTime, startTime),
            endValue,
            "Should return end value at start time for zero duration"
        );

        // Test after start time
        vm.warp(startTime + 1);
        assertEq(
            mock.getInterpolatedValue(startValue, endValue, startTime, startTime),
            endValue,
            "Should return end value after start time for zero duration"
        );

        uint256 bigVal = 1e18 * FP_ONE; //1 quintillion w/ 18 decimals

        // Test exact endpoints
        vm.warp(0);
        assertEq(mock.getInterpolatedValue(0, bigVal, 0, bigVal), 0, "Should be 0 at start time");
        vm.warp(bigVal);
        assertEq(mock.getInterpolatedValue(0, bigVal, 0, bigVal), bigVal, "Should be bigVal at end time");

        // Test intermediate points
        uint256 steps = 1e4;
        for (uint256 i = 0; i <= steps; i++) {
            uint256 currentTime = (bigVal / steps) * i;
            vm.warp(currentTime);
            uint256 expectedValue = (bigVal / steps) * i;

            uint256 actualValue;
            try mock.getInterpolatedValue(0, bigVal, 0, bigVal) returns (uint256 value) {
                actualValue = value;
                assertApproxEqRel(actualValue, expectedValue, 1, "Should be close for large numbers");
            } catch Error(string memory reason) {
                revert(string(abi.encodePacked("getInterpolatedValue reverted: ", reason)));
            } catch (bytes memory /*lowLevelData*/) {
                revert("getInterpolatedValue reverted unexpectedly");
            }

            // Additional check to ensure the value is within the expected range
            assertGe(actualValue, 0, "Value should not be less than 0");
            assertLe(actualValue, bigVal, "Value should not exceed bigVal");
        }
    }
}
