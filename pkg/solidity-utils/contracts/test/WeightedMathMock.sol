// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "../math/WeightedMath.sol";

contract WeightedMathMock {
    function computeInvariant(
        uint256[] memory normalizedWeights,
        uint256[] memory balances
    ) external pure returns (uint256) {
        return WeightedMath.computeInvariant(normalizedWeights, balances);
    }

    function computeOutGivenExactIn(
        uint256 balanceIn,
        uint256 weightIn,
        uint256 balanceOut,
        uint256 weightOut,
        uint256 amountIn
    ) external pure returns (uint256) {
        return WeightedMath.computeOutGivenExactIn(balanceIn, weightIn, balanceOut, weightOut, amountIn);
    }

    function computeInGivenExactOut(
        uint256 balanceIn,
        uint256 weightIn,
        uint256 balanceOut,
        uint256 weightOut,
        uint256 amountOut
    ) external pure returns (uint256) {
        return WeightedMath.computeInGivenExactOut(balanceIn, weightIn, balanceOut, weightOut, amountOut);
    }
}
