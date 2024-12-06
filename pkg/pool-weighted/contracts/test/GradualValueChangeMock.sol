// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "../lib/GradualValueChange.sol";

contract GradualValueChangeMock {
    function getInterpolatedValue(
        uint256 startValue,
        uint256 endValue,
        uint256 startTime,
        uint256 endTime
    ) public view returns (uint256) {
        return GradualValueChange.getInterpolatedValue(startValue, endValue, startTime, endTime);
    }

    function resolveStartTime(uint256 startTime, uint256 endTime) public view returns (uint256) {
        return GradualValueChange.resolveStartTime(startTime, endTime);
    }

    function interpolateValue(uint256 startValue, uint256 endValue, uint256 pctProgress) public pure returns (uint256) {
        return GradualValueChange.interpolateValue(startValue, endValue, pctProgress);
    }

    function calculateValueChangeProgress(uint256 startTime, uint256 endTime) public view returns (uint256) {
        return GradualValueChange.calculateValueChangeProgress(startTime, endTime);
    }
}
