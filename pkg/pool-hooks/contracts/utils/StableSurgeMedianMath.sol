// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

library StableSurgeMedianMath {
    function calculateImbalance(uint256[] memory balances) internal pure returns (uint256) {
        uint256[] memory sortedBalances = _sort(balances);
        uint256 median = _findMedian(sortedBalances);

        uint256 totalBalance = 0;
        uint256 totalDiff = 0;

        for (uint i = 0; i < balances.length; i++) {
            totalBalance += balances[i];
            totalDiff += _absSub(balances[i], median);
        }

        return (totalDiff * 1e18) / totalBalance;
    }

    function _findMedian(uint256[] memory sortedBalances) internal pure returns (uint256) {
        uint256 mid = sortedBalances.length / 2;

        if (sortedBalances.length % 2 == 0) {
            return (sortedBalances[mid - 1] + sortedBalances[mid]) / 2;
        } else {
            return sortedBalances[mid];
        }
    }

    // First implementation had quickselect algorithm, but it was removed in the final version
    // because it seems to be overhead for small arrays (up to 8 elements)
    // Complexity of this insertion sort is O(n^2) but it is not a problem for small arrays
    function _sort(uint256[] memory balances) internal pure returns (uint256[] memory sortedBalances) {
        uint256 length = balances.length;
        sortedBalances = new uint256[](length);

        for (uint i = 0; i < length; i++) {
            sortedBalances[i] = balances[i];
        }

        for (uint i = 1; i < length; i++) {
            uint256 value = sortedBalances[i];

            uint256 j = i;
            while (j > 0 && sortedBalances[j - 1] > value) {
                sortedBalances[j] = sortedBalances[j - 1];
                j--;
            }

            sortedBalances[j] = value;
        }
    }

    function _absSub(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : b - a;
    }
}
