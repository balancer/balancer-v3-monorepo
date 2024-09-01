// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { Rounding } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/BasePoolTypes.sol";

import { WeightedMath } from "@balancer-labs/v3-solidity-utils/contracts/math/WeightedMath.sol";

contract WeightedMathMock {
    function computeInvariant(
        uint256[] memory normalizedWeights,
        uint256[] memory balances,
        Rounding rounding
    ) external pure returns (uint256) {
        if (rounding == Rounding.ROUND_DOWN) {
            return WeightedMath.computeInvariantDown(normalizedWeights, balances);
        } else {
            return WeightedMath.computeInvariantUp(normalizedWeights, balances);
        }
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
