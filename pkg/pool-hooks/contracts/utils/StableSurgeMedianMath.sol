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
     * NB: `balances` is mutated and unusable after this call: any access will revert.
     */
    function calculateImbalance(uint256[] memory balances) internal pure returns (uint256 imbalance) {
        uint256 median = _findMedian(balances);
        uint256 totalBalance = 0;
        uint256 totalDiff = 0;

        for (uint256 i = 0; i < balances.length; i++) {
            totalBalance += balances[i];
            totalDiff += absSub(balances[i], median);
        }

        imbalance = totalDiff.divDown(totalBalance);

        // Zero the length field in shared memory so any post-call access to balances reverts out-of-bounds.
        // The array was sorted in place by _findMedian; this prevents callers from silently reading sorted values
        // expecting the original order. Unlike `delete balances` (which only resets the local stack variable),
        // `mstore` writes directly to the memory location both caller and callee share.
        // solhint-disable-next-line no-inline-assembly
        assembly ("memory-safe") {
            mstore(balances, 0)
        }
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
        balances.sort();
        uint256 mid = balances.length / 2;
        if (balances.length % 2 == 0) {
            return (balances[mid - 1] + balances[mid]) / 2;
        } else {
            return balances[mid];
        }
    }
}
