// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IWeightedPool } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/IWeightedPool.sol";

import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { GradualValueChange } from "./GradualValueChange.sol";

library LBPoolLib {
    // LBPs are constrained to two tokens.
    uint256 public constant NUM_TOKENS = 2;

    // Matches Weighted Pool min weight.
    uint256 internal constant _MIN_WEIGHT = 1e16; // 1%

    /**
     * @dev Normalize `startTime` to block.now (`actualStartTime`) if it's in the past, and verify that
     * `endTime` > `actualStartTime` as well as token weights.
     */
    function verifyWeightUpdateParameters(
        uint256 startTime,
        uint256 endTime,
        uint256[] memory startWeights,
        uint256[] memory endWeights
    ) internal view returns (uint256 actualStartTime) {
        InputHelpers.ensureInputLengthMatch(NUM_TOKENS, startWeights.length);
        InputHelpers.ensureInputLengthMatch(NUM_TOKENS, endWeights.length);

        if (endWeights[0] < _MIN_WEIGHT || endWeights[1] < _MIN_WEIGHT) {
            revert IWeightedPool.MinWeight();
        }
        if (endWeights[0] + endWeights[1] != FixedPoint.ONE) {
            revert IWeightedPool.NormalizedWeightInvariant();
        }

        actualStartTime = GradualValueChange.resolveStartTime(startTime, endTime);

        return actualStartTime;
    }
}
