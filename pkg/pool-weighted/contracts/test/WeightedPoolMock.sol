// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import "../WeightedPool.sol";

contract WeightedPoolMock is WeightedPool {
    // Local storage of weights, so that they can be changed for tests.
    uint256[] private _normalizedWeights;

    constructor(NewPoolParams memory params, IVault vault) WeightedPool(params, vault) {
        _normalizedWeights = new uint256[](params.numTokens);

        for (uint256 i = 0; i < params.numTokens; ++i) {
            _normalizedWeights[i] = params.normalizedWeights[i];
        }
    }

    function setNormalizedWeight(uint256 tokenIndex, uint256 newWeight) external {
        if (tokenIndex < _normalizedWeights.length) {
            _normalizedWeights[tokenIndex] = newWeight;
        }
    }

    // Helper for most common case of setting weights - for two token pools.
    function setNormalizedWeights(uint256[2] memory newWeights) external {
        require(newWeights[0] + newWeights[1] == FixedPoint.ONE, "Weights don't total 1");

        _normalizedWeights[0] = newWeights[0];
        _normalizedWeights[1] = newWeights[1];
    }

    function _getNormalizedWeight(uint256 tokenIndex) internal view override returns (uint256) {
        if (tokenIndex < _normalizedWeights.length) {
            return _normalizedWeights[tokenIndex];
        } else {
            revert IVaultErrors.InvalidToken();
        }
    }

    function _getNormalizedWeights() internal view override returns (uint256[] memory) {
        return _normalizedWeights;
    }
}
