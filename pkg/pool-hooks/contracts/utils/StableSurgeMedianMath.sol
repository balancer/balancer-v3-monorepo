// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { ScalingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ScalingHelpers.sol";
import { Arrays } from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/Arrays.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

library StableSurgeMedianMath {
    using Arrays for uint256[];
    using FixedPoint for uint256;

    function calculateImbalance(uint256[] memory balances) internal pure returns (uint256) {
        uint256 median = findMedian(balances);

        uint256 totalBalance = 0;
        uint256 totalDiff = 0;

        for (uint i = 0; i < balances.length; i++) {
            totalBalance += balances[i];
            totalDiff += absSub(balances[i], median);
        }

        return totalDiff.divDown(totalBalance);
    }

    function findMedian(uint256[] memory balances) internal pure returns (uint256) {
        // We do not want to mutate the original balances array, so we copy it to a new array for sorting.
        uint256[] memory sortedBalances = new uint256[](balances.length);
        ScalingHelpers.copyToArray(balances, sortedBalances);

        sortedBalances.sort();
        uint256 mid = sortedBalances.length / 2;

        if (sortedBalances.length % 2 == 0) {
            return (sortedBalances[mid - 1] + sortedBalances[mid]) / 2;
        } else {
            return sortedBalances[mid];
        }
    }

    function absSub(uint256 a, uint256 b) internal pure returns (uint256) {
        unchecked {
            return a > b ? a - b : b - a;
        }
    }
}
