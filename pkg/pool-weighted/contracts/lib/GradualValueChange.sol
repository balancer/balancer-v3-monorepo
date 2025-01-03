// SPDX-License-Identifier: GPL-3.0-or-later

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

pragma solidity ^0.8.24;

// solhint-disable not-rely-on-time

library GradualValueChange {
    /// @dev Indicates that the start time is after the end time
    error GradualUpdateTimeTravel(uint256 resolvedStartTime, uint256 endTime);

    using FixedPoint for uint256;

    function getInterpolatedValue(
        uint256 startValue,
        uint256 endValue,
        uint256 startTime,
        uint256 endTime
    ) internal view returns (uint256) {
        uint256 pctProgress = calculateValueChangeProgress(startTime, endTime);

        return interpolateValue(startValue, endValue, pctProgress);
    }

    function resolveStartTime(uint256 startTime, uint256 endTime) internal view returns (uint256 resolvedStartTime) {
        // If the start time is in the past, "fast forward" to start now
        // This avoids discontinuities in the value curve. Otherwise, if you set the start/end times with
        // only 10% of the period in the future, the value would immediately jump 90%
        resolvedStartTime = Math.max(block.timestamp, startTime);

        if (resolvedStartTime > endTime) {
            revert GradualUpdateTimeTravel(resolvedStartTime, endTime);
        }
    }

    function interpolateValue(
        uint256 startValue,
        uint256 endValue,
        uint256 pctProgress
    ) internal pure returns (uint256) {
        if (pctProgress >= FixedPoint.ONE || startValue == endValue) {
            return endValue;
        }

        if (pctProgress == 0) {
            return startValue;
        }

        unchecked {
            if (startValue > endValue) {
                uint256 delta = pctProgress.mulDown(startValue - endValue);
                return startValue - delta;
            } else {
                uint256 delta = pctProgress.mulDown(endValue - startValue);
                return startValue + delta;
            }
        }
    }

    /**
     * @dev Returns a fixed-point number representing how far along the current value change is, where 0 means the
     * change has not yet started, and FixedPoint.ONE means it has fully completed.
     */
    function calculateValueChangeProgress(uint256 startTime, uint256 endTime) internal view returns (uint256) {
        if (block.timestamp >= endTime) {
            return FixedPoint.ONE;
        } else if (block.timestamp <= startTime) {
            return 0;
        }

        // No need for checked math as the magnitudes are verified above: endTime > block.timestamp > startTime
        uint256 totalSeconds;
        uint256 secondsElapsed;

        unchecked {
            totalSeconds = endTime - startTime;
            secondsElapsed = block.timestamp - startTime;
        }

        // We don't need to consider zero division here as this is covered above.
        return secondsElapsed.divDown(totalSeconds);
    }
}
