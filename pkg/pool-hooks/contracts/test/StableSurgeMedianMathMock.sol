// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { StableSurgeMedianMath } from "../utils/StableSurgeMedianMath.sol";

contract StableSurgeMedianMathMock {
    function calculateImbalance(uint256[] memory balances) public pure returns (uint) {
        return StableSurgeMedianMath.calculateImbalance(balances);
    }

    function findMedian(uint256[] memory sortedBalances) public pure returns (uint256) {
        return StableSurgeMedianMath.findMedian(sortedBalances);
    }

    function sort(uint256[] memory balances) public pure returns (uint256[] memory) {
        return StableSurgeMedianMath.sort(balances);
    }

    function absSub(uint256 a, uint256 b) public pure returns (uint256) {
        return StableSurgeMedianMath.absSub(a, b);
    }
}
