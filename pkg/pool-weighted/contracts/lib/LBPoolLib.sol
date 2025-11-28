// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IWeightedPool } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/IWeightedPool.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

library LBPoolLib {
    // Matches Weighted Pool min weight.
    uint256 internal constant _MIN_WEIGHT = 1e16; // 1%

    function verifyWeightUpdateParameters(
        uint256 projectStartWeight,
        uint256 reserveStartWeight,
        uint256 projectEndWeight,
        uint256 reserveEndWeight
    ) internal pure {
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
    }
}
