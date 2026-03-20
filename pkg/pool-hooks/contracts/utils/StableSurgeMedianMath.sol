// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { ScalingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ScalingHelpers.sol";
import { Arrays } from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/Arrays.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

library StableSurgeMedianMath {
    using FixedPoint for uint256;
    using Arrays for uint256[];

    /**
     * @notice Calculate the imbalance of a set of balances relative to their median.
     * @dev Returns totalAbsDeviation / totalBalance, where deviation is measured from the median.
     */
    function calculateImbalance(uint256[] memory balances) internal pure returns (uint256) {
        uint256 median = _findMedian(balances);
        uint256 totalBalance = 0;
        uint256 totalDiff = 0;

        for (uint256 i = 0; i < balances.length; i++) {
            totalBalance += balances[i];
            totalDiff += absSub(balances[i], median);
        }

        return totalDiff.divDown(totalBalance);
    }

    /// @dev Returns the absolute difference of two uint256 values.
    function absSub(uint256 a, uint256 b) internal pure returns (uint256) {
        unchecked {
            return a > b ? a - b : b - a;
        }
    }

    /**
     * @notice Finds the median of `balances` by sorting the array in place.
     * @dev For even-length arrays, it returns the average of the two middle elements. For odd-length arrays, it
     * returns the middle element.
     *
     * WARNING: sorts `balances` in place. The caller's array is modified after this call. This function is internal
     * with an underscore prefix to signal that external callers should not use it directly. The intended entry point
     * is `calculateImbalance`.
     */
    // solhint-disable-next-line private-vars-leading-underscore
    function _findMedian(uint256[] memory balances) internal pure returns (uint256) {
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
}
