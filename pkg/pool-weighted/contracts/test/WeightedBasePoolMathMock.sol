// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { WeightedMath } from "@balancer-labs/v3-solidity-utils/contracts/math/WeightedMath.sol";
import { Rounding } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { BasePoolMathMock } from "@balancer-labs/v3-vault/contracts/test/BasePoolMathMock.sol";

// Mock Weighted5050 to test rounding in BasePoolMath for consistency with other implementations.
contract WeightedBasePoolMathMock is BasePoolMathMock {
    uint256[] public weights;

    constructor(uint256[] memory _weights) {
        weights = _weights;
    }

    function computeInvariant(
        uint256[] memory balancesLiveScaled18,
        Rounding rounding
    ) public view override returns (uint256) {
        if (rounding == Rounding.ROUND_DOWN) {
            return WeightedMath.computeInvariantDown(weights, balancesLiveScaled18);
        } else {
            return WeightedMath.computeInvariantUp(weights, balancesLiveScaled18);
        }
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
