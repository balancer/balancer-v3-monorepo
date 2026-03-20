// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { Arrays } from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/Arrays.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

library StableSurgeMedianMath {
    using FixedPoint for uint256;
    using Arrays for uint256[];

    /**
     * @notice Calculate the imbalance of a set of balances relative to their median.
     * @dev Returns totalAbsDeviation / totalBalance, where deviation is measured from the median.
     *
     * WARNING: This function deletes the `balances` array before returning. Any access to `balances` after this call
     * will revert with an out-of-bounds error. This is intentional: `_findMedian` sorts the array in place, so the
     * caller's array would be in an unexpected order after this call. Deleting it converts a potential silent bug
     * (reading sorted values when expecting original order) into a revert.
     *
     * Callers must extract all needed values from `balances` before calling this function.
     */
    function calculateImbalance(uint256[] memory balances) internal pure returns (uint256 imbalance) {
        // Accumulate totals before calling _findMedian, which sorts balances in place. After _findMedian, the array
        // is sorted (still valid for arithmetic), but we complete all reads here to make the deletion below safe.
        uint256 totalBalance = 0;
        uint256 length = balances.length;
        for (uint256 i = 0; i < length; i++) {
            totalBalance += balances[i];
        }

        uint256 median = _findMedian(balances);

        uint256 totalDiff = 0;
        for (uint256 i = 0; i < length; i++) {
            totalDiff += absSub(balances[i], median);
        }

        imbalance = totalDiff.divDown(totalBalance);

        // Delete the array so that any future access to `balances` reverts out-of-bounds.
        // This prevents callers from silently reading sorted values when they expect the original order.
        // See function NatSpec for details.
        delete balances;
    }

    /// @dev Returns the absolute difference of two uint256 values.
    function absSub(uint256 a, uint256 b) internal pure returns (uint256) {
        unchecked {
            return a > b ? a - b : b - a;
        }
    }

    /**
     * @dev Finds the median of `balances` by sorting the array in place.
     *
     * WARNING: sorts `balances` in place. The caller's array is modified after this call. This function is internal
     * with an underscore prefix to signal that external callers should not use it directly -- the mutation is
     * surprising and the `delete` trap in `calculateImbalance` will not apply. Use `calculateImbalance` as the
     * intended entry point.
     *
     * For even-length arrays returns the average of the two middle elements.
     * For odd-length arrays returns the middle element.
     */
    // solhint-disable-next-line private-vars-leading-underscore
    function _findMedian(uint256[] memory balances) internal pure returns (uint256) {
        balances.sort();
        uint256 mid = balances.length / 2;
        if (balances.length % 2 == 0) {
            return (balances[mid - 1] + balances[mid]) / 2;
        } else {
            return balances[mid];
        }
    }
}
