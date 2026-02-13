// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IWeightedPool } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/IWeightedPool.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

library LBPoolLib {
    // Matches Weighted Pool min weight.
    uint256 internal constant _MIN_WEIGHT = 1e16; // 1%

    /**
     * @notice Ensure starting and ending weights are valid for weighted pools.
     * @dev Standard LBPs allow for price discovery in the beginning, and price stability over the course of the sale.
     * However, we do not enforce this as a constraint (in this or any previous versions), which allows maximum
     * flexibility and enables potential non-standard use cases. Of course, it is also possible to misconfigure an LBP
     * with "backwards" weights (which happened at least once in V1), potentially leading to arbitrage loss.
     *
     * This version mitigates that risk to some degree by enforcing an initialization period before the sale, and
     * preventing trades before the start time. This allows time to fix any mistakes of this nature before any
     * adverse arbitrage trades could occur.
     */
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
