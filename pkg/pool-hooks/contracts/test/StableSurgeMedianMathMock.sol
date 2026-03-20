// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { StableSurgeMedianMath } from "../utils/StableSurgeMedianMath.sol";

contract StableSurgeMedianMathMock {
    function calculateImbalance(uint256[] memory balancesScaled18) public pure returns (uint) {
        return StableSurgeMedianMath.calculateImbalance(balancesScaled18);
    }

    function findMedian(uint256[] memory sortedBalancesScaled18) public pure returns (uint256) {
        return StableSurgeMedianMath._findMedian(sortedBalancesScaled18);
    }

    function absSub(uint256 a, uint256 b) public pure returns (uint256) {
        return StableSurgeMedianMath.absSub(a, b);
    }

    function calculateImbalanceAndAccessAfterward(uint256[] memory balances) public pure returns (uint256) {
        StableSurgeMedianMath.calculateImbalance(balances);

        return balances[0];
    }
}
