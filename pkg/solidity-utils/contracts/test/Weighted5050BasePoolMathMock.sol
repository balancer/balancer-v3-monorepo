// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/math/Math.sol";

import { WeightedMath } from "@balancer-labs/v3-solidity-utils/contracts/math/WeightedMath.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";

import "../math/FixedPoint.sol";
import "./BasePoolMathMock.sol";

contract Weighted5050BasePoolMathMock is BasePoolMathMock {
    using ArrayHelpers for *;
    using FixedPoint for uint256;

    function computeInvariant(uint256[] memory balancesLiveScaled18) public pure override returns (uint256) {
        return WeightedMath.computeInvariant([uint256(50e16), uint256(50e16)].toMemoryArray(), balancesLiveScaled18);
    }

    function computeBalance(
        uint256[] memory balancesLiveScaled18,
        uint256 tokenInIndex,
        uint256 invariantRatio
    ) external pure override returns (uint256 newBalance) {
        return WeightedMath.computeBalanceOutGivenInvariant(balancesLiveScaled18[tokenInIndex], 50e16, invariantRatio);
    }
}
