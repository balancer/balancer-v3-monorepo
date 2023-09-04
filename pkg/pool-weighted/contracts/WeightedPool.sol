// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { WeightedMath } from "@balancer-labs/v3-solidity-utils/contracts/math/WeightedMath.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { ScalingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ScalingHelpers.sol";
import { IVault, PoolConfig } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IWeightedPool } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/IWeightedPool.sol";

/**
 * @dev Basic Weighted Pool with immutable weights.
 */
contract WeightedPool is IWeightedPool {
    using FixedPoint for uint256;
    using ScalingHelpers for IERC20;

    IERC20 internal immutable _token0;
    IERC20 internal immutable _token1;

    // All token balances are normalized to behave as if the token had 18 decimals. We assume a token's decimals will
    // not change throughout its lifetime, and store the corresponding scaling factor for each at construction time.
    // These factors are always greater than or equal to one: tokens with more than 18 decimals are not supported.

    uint256 internal immutable _scalingFactor0;
    uint256 internal immutable _scalingFactor1;

    uint256 internal immutable _normalizedWeight0;
    uint256 internal immutable _normalizedWeight1;

    struct NewPoolParams {
        string name;
        string symbol;
        IERC20[] tokens;
        uint256[] normalizedWeights;
    }

    constructor(
        NewPoolParams memory params,
        IVault vault,
        uint256 pauseWindowDuration,
        uint256 bufferPeriodDuration,
        address owner
    ) {
        uint256 numTokens = params.tokens.length;
        InputHelpers.ensureInputLengthMatch(numTokens, params.normalizedWeights.length);

        // Ensure each normalized weight is above the minimum
        uint256 normalizedSum = 0;
        for (uint8 i = 0; i < numTokens; i++) {
            uint256 normalizedWeight = params.normalizedWeights[i];

            if (normalizedWeight < WeightedMath._MIN_WEIGHT) {
                revert MinWeight();
            }
            normalizedSum = normalizedSum + normalizedWeight;
        }
        // Ensure that the normalized weights sum to ONE
        if (normalizedSum != FixedPoint.ONE) {
            revert NormalizedWeightInvariant();
        }

        // Immutable variables cannot be initialized inside an if statement, so we must do conditional assignments
        _token0 = params.tokens[0];
        _token1 = params.tokens[1];

        _scalingFactor0 = params.tokens[0].computeScalingFactor();
        _scalingFactor1 = params.tokens[1].computeScalingFactor();

        _normalizedWeight0 = params.normalizedWeights[0];
        _normalizedWeight1 = params.normalizedWeights[1];
    }

    function _getNormalizedWeight(IERC20 token) internal view virtual returns (uint256) {
        // prettier-ignore
        if (token == _token0) { return _normalizedWeight0; }
        else if (token == _token1) { return _normalizedWeight1; }
        else {
            revert InvalidToken();
        }
    }

    function _getNormalizedWeights() internal view virtual returns (uint256[] memory) {
        uint256[] memory normalizedWeights = new uint256[](2);

        normalizedWeights[0] = _normalizedWeight0;
        normalizedWeights[1] = _normalizedWeight1;

        return normalizedWeights;
    }

    function _getMaxTokens() internal pure virtual returns (uint256) {
        return 2;
    }

    function _getTotalTokens() internal view virtual returns (uint256) {
        return 2;
    }

    /**
     * @dev Returns the scaling factor for one of the Pool's tokens. Reverts if `token` is not a token registered by the
     * Pool.
     */
    function _scalingFactor(IERC20 token) internal view virtual returns (uint256) {
        // prettier-ignore
        if (token == _token0) { return _getScalingFactor0(); }
        else if (token == _token1) { return _getScalingFactor1(); }
        else {
            revert InvalidToken();
        }
    }

    function _scalingFactors() internal view virtual returns (uint256[] memory) {
        uint256[] memory scalingFactors = new uint256[](2);

        scalingFactors[0] = _getScalingFactor0();
        scalingFactors[1] = _getScalingFactor1();

        return scalingFactors;
    }

    function _getScalingFactor0() internal view returns (uint256) {
        return _scalingFactor0;
    }

    function _getScalingFactor1() internal view returns (uint256) {
        return _scalingFactor1;
    }
}
