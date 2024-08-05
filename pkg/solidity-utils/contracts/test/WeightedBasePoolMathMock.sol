// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { WeightedMath } from "../math/WeightedMath.sol";
import "./BasePoolMathMock.sol";

// Mock Weighted5050 to test rounding in BasePoolMath for consistency with other implementations.
contract WeightedBasePoolMathMock is BasePoolMathMock {
    uint256[] public weights;

    constructor(uint256[] memory _weights) {
        weights = _weights;
    }

    function computeInvariant(uint256[] memory balancesLiveScaled18) public view override returns (uint256) {
        return WeightedMath.computeInvariant(weights, balancesLiveScaled18);
    }

    function computeBalance(
        uint256[] memory balancesLiveScaled18,
        uint256 tokenInIndex,
        uint256 invariantRatio
    ) external view override returns (uint256 newBalance) {
        return
            WeightedMath.computeBalanceOutGivenInvariant(
                balancesLiveScaled18[tokenInIndex],
                weights[tokenInIndex],
                invariantRatio
            );
    }
}
