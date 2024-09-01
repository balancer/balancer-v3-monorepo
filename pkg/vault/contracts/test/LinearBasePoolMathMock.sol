// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { Rounding } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/BasePoolTypes.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import "./BasePoolMathMock.sol";

// Mock the linear math that we use in pool mocks for testing.
contract LinearBasePoolMathMock is BasePoolMathMock {
    using FixedPoint for uint256;

    function computeInvariant(uint256[] memory balances, Rounding) public pure override returns (uint256) {
        // inv = x + y
        uint256 invariant;
        for (uint256 i = 0; i < balances.length; ++i) {
            invariant += balances[i];
        }
        return invariant;
    }

    function computeBalance(
        uint256[] memory balances,
        uint256 tokenInIndex,
        uint256 invariantRatio
    ) external pure override returns (uint256 newBalance) {
        // inv = x + y
        uint256 invariant = computeInvariant(balances, Rounding.ROUND_DOWN);
        return (balances[tokenInIndex] + invariant.mulDown(invariantRatio)) - invariant;
    }
}
