// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IWeightedPool } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/IWeightedPool.sol";

import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { GradualValueChange } from "./GradualValueChange.sol";

library LBPoolLib {
    // Matches Weighted Pool min weight.
    uint256 internal constant _MIN_WEIGHT = 1e16; // 1%

    /**
     * @dev Normalize `startTime` to block.now (`actualStartTime`) if it's in the past, and verify that
     * `endTime` > `actualStartTime` as well as token weights.
     */
    function verifyWeightUpdateParameters(
        uint256 startTime,
        uint256 endTime,
        uint256 projectStartWeight,
        uint256 reserveStartWeight,
        uint256 projectEndWeight,
        uint256 reserveEndWeight
    ) internal view returns (uint256 actualStartTime) {
        if (
            projectStartWeight < _MIN_WEIGHT ||
            reserveStartWeight < _MIN_WEIGHT ||
            projectEndWeight < _MIN_WEIGHT ||
            reserveEndWeight < _MIN_WEIGHT
        ) {
            revert IWeightedPool.MinWeight();
        }

        if (
            projectStartWeight + reserveStartWeight != FixedPoint.ONE ||
            projectEndWeight + reserveEndWeight != FixedPoint.ONE
        ) {
            revert IWeightedPool.NormalizedWeightInvariant();
        }

        actualStartTime = GradualValueChange.resolveStartTime(startTime, endTime);

        return actualStartTime;
    }
}
