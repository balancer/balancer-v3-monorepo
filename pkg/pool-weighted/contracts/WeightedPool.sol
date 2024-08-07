// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import {
    IWeightedPool,
    WeightedPoolDynamicData,
    WeightedPoolImmutableData
} from "@balancer-labs/v3-interfaces/contracts/pool-weighted/IWeightedPool.sol";
import { ISwapFeePercentageBounds } from "@balancer-labs/v3-interfaces/contracts/vault/ISwapFeePercentageBounds.sol";
import {
    IUnbalancedLiquidityInvariantRatioBounds
} from "@balancer-labs/v3-interfaces/contracts/vault/IUnbalancedLiquidityInvariantRatioBounds.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { SwapKind, PoolSwapParams } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";

import { BalancerPoolToken } from "@balancer-labs/v3-vault/contracts/BalancerPoolToken.sol";
import { PoolInfo } from "@balancer-labs/v3-pool-utils/contracts/PoolInfo.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { WeightedMath } from "@balancer-labs/v3-solidity-utils/contracts/math/WeightedMath.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { Version } from "@balancer-labs/v3-solidity-utils/contracts/helpers/Version.sol";

/**
 * @notice Standard Balancer Weighted Pool, with fixed weights.
 * @dev Weighted Pools are designed for uncorrelated assets, and use `WeightedMath` (from Balancer v1 and v2)
 * to compute the price curve.
 *
 * There can be up to 8 tokens in a weighted pool (same as v2), and the normalized weights (expressed as 18-decimal
 * floating point numbers), must sum to FixedPoint.ONE. Weights cannot be changed after deployment.
 *
 * The swap fee percentage is bounded by minimum and maximum values (same as were used in v2).
 */
contract WeightedPool is IWeightedPool, BalancerPoolToken, PoolInfo, Version {
    // Fees are 18-decimal, floating point values, which will be stored in the Vault using 24 bits.
    // This means they have 0.00001% resolution (i.e., any non-zero bits < 1e11 will cause precision loss).
    // Minimum values help make the math well-behaved (i.e., the swap fee should overwhelm any rounding error).
    // Maximum values protect users by preventing permissioned actors from setting excessively high swap fees.
    uint256 private constant _MIN_SWAP_FEE_PERCENTAGE = 1e12; // 0.0001%
    uint256 private constant _MAX_SWAP_FEE_PERCENTAGE = 10e16; // 10%

    // A minimum normalized weight imposes a maximum weight ratio. We need this due to limitations in the
    // implementation of the fixed point power function, as these ratios are often exponents.
    uint256 private constant _MIN_WEIGHT = 1e16; // 1%

    uint256 private immutable _totalTokens;

    uint256 internal immutable _normalizedWeight0;
    uint256 internal immutable _normalizedWeight1;
    uint256 internal immutable _normalizedWeight2;
    uint256 internal immutable _normalizedWeight3;
    uint256 internal immutable _normalizedWeight4;
    uint256 internal immutable _normalizedWeight5;
    uint256 internal immutable _normalizedWeight6;
    uint256 internal immutable _normalizedWeight7;

    struct NewPoolParams {
        string name;
        string symbol;
        uint256 numTokens;
        uint256[] normalizedWeights;
        string version;
    }

    /// @dev Indicates that one of the pool tokens' weight is below the minimum allowed.
    error MinWeight();

    /// @dev Indicates that the sum of the pool tokens' weights is not FP 1.
    error NormalizedWeightInvariant();

    constructor(
        NewPoolParams memory params,
        IVault vault
    ) BalancerPoolToken(vault, params.name, params.symbol) PoolInfo(vault) Version(params.version) {
        _totalTokens = params.numTokens;
        InputHelpers.ensureInputLengthMatch(_totalTokens, params.normalizedWeights.length);

        // Ensure each normalized weight is above the minimum
        uint256 normalizedSum = 0;
        for (uint8 i = 0; i < _totalTokens; ++i) {
            uint256 normalizedWeight = params.normalizedWeights[i];

            if (normalizedWeight < _MIN_WEIGHT) {
                revert MinWeight();
            }
            normalizedSum = normalizedSum + normalizedWeight;

            // prettier-ignore
            if (i == 0) { _normalizedWeight0 = normalizedWeight; }
            else if (i == 1) { _normalizedWeight1 = normalizedWeight; }
            else if (i == 2) { _normalizedWeight2 = normalizedWeight; }
            else if (i == 3) { _normalizedWeight3 = normalizedWeight; }
            else if (i == 4) { _normalizedWeight4 = normalizedWeight; }
            else if (i == 5) { _normalizedWeight5 = normalizedWeight; }
            else if (i == 6) { _normalizedWeight6 = normalizedWeight; }
            else if (i == 7) { _normalizedWeight7 = normalizedWeight; }
        }

        // Ensure that the normalized weights sum to ONE
        if (normalizedSum != FixedPoint.ONE) {
            revert NormalizedWeightInvariant();
        }
    }

    /// @inheritdoc IBasePool
    function computeInvariant(uint256[] memory balancesLiveScaled18) public view returns (uint256) {
        return WeightedMath.computeInvariant(_getNormalizedWeights(), balancesLiveScaled18);
    }

    /// @inheritdoc IBasePool
    function computeBalance(
        uint256[] memory balancesLiveScaled18,
        uint256 tokenInIndex,
        uint256 invariantRatio
    ) external view returns (uint256 newBalance) {
        return
            WeightedMath.computeBalanceOutGivenInvariant(
                balancesLiveScaled18[tokenInIndex],
                _getNormalizedWeight(tokenInIndex),
                invariantRatio
            );
    }

    /// @inheritdoc IWeightedPool
    function getNormalizedWeights() external view returns (uint256[] memory) {
        return _getNormalizedWeights();
    }

    /// @inheritdoc IBasePool
    function onSwap(PoolSwapParams memory request) public view onlyVault returns (uint256) {
        uint256 balanceTokenInScaled18 = request.balancesScaled18[request.indexIn];
        uint256 balanceTokenOutScaled18 = request.balancesScaled18[request.indexOut];

        if (request.kind == SwapKind.EXACT_IN) {
            uint256 amountOutScaled18 = WeightedMath.computeOutGivenExactIn(
                balanceTokenInScaled18,
                _getNormalizedWeight(request.indexIn),
                balanceTokenOutScaled18,
                _getNormalizedWeight(request.indexOut),
                request.amountGivenScaled18
            );

            return amountOutScaled18;
        } else {
            uint256 amountInScaled18 = WeightedMath.computeInGivenExactOut(
                balanceTokenInScaled18,
                _getNormalizedWeight(request.indexIn),
                balanceTokenOutScaled18,
                _getNormalizedWeight(request.indexOut),
                request.amountGivenScaled18
            );

            // Fees are added after scaling happens, to reduce the complexity of the rounding direction analysis.
            return amountInScaled18;
        }
    }

    function _getNormalizedWeight(uint256 tokenIndex) internal view virtual returns (uint256) {
        // prettier-ignore
        if (tokenIndex == 0) { return _normalizedWeight0; }
        else if (tokenIndex == 1) { return _normalizedWeight1; }
        else if (tokenIndex == 2) { return _normalizedWeight2; }
        else if (tokenIndex == 3) { return _normalizedWeight3; }
        else if (tokenIndex == 4) { return _normalizedWeight4; }
        else if (tokenIndex == 5) { return _normalizedWeight5; }
        else if (tokenIndex == 6) { return _normalizedWeight6; }
        else if (tokenIndex == 7) { return _normalizedWeight7; }
        else {
            revert IVaultErrors.InvalidToken();
        }
    }

    function _getNormalizedWeights() internal view virtual returns (uint256[] memory) {
        uint256 totalTokens = _totalTokens;
        uint256[] memory normalizedWeights = new uint256[](totalTokens);

        // prettier-ignore
        {
            normalizedWeights[0] = _normalizedWeight0;
            normalizedWeights[1] = _normalizedWeight1;
            if (totalTokens > 2) { normalizedWeights[2] = _normalizedWeight2; } else { return normalizedWeights; }
            if (totalTokens > 3) { normalizedWeights[3] = _normalizedWeight3; } else { return normalizedWeights; }
            if (totalTokens > 4) { normalizedWeights[4] = _normalizedWeight4; } else { return normalizedWeights; }
            if (totalTokens > 5) { normalizedWeights[5] = _normalizedWeight5; } else { return normalizedWeights; }
            if (totalTokens > 6) { normalizedWeights[6] = _normalizedWeight6; } else { return normalizedWeights; }
            if (totalTokens > 7) { normalizedWeights[7] = _normalizedWeight7; }
        }

        return normalizedWeights;
    }

    /// @inheritdoc ISwapFeePercentageBounds
    function getMinimumSwapFeePercentage() external pure returns (uint256) {
        return _MIN_SWAP_FEE_PERCENTAGE;
    }

    /// @inheritdoc ISwapFeePercentageBounds
    function getMaximumSwapFeePercentage() external pure returns (uint256) {
        return _MAX_SWAP_FEE_PERCENTAGE;
    }

    /// @inheritdoc IUnbalancedLiquidityInvariantRatioBounds
    function getMinimumInvariantRatio() external pure returns (uint256) {
        return WeightedMath._MIN_INVARIANT_RATIO;
    }

    /// @inheritdoc IUnbalancedLiquidityInvariantRatioBounds
    function getMaximumInvariantRatio() external pure returns (uint256) {
        return WeightedMath._MAX_INVARIANT_RATIO;
    }

    /// @inheritdoc IWeightedPool
    function getWeightedPoolDynamicData() external view returns (WeightedPoolDynamicData memory data) {
        data.balancesLiveScaled18 = _vault.getCurrentLiveBalances(address(this));
        (, data.tokenRates) = _vault.getPoolTokenRates(address(this));
        data.staticSwapFeePercentage = _vault.getStaticSwapFeePercentage((address(this)));
        data.totalSupply = totalSupply();
        data.bptRate = getRate();
    }

    /// @inheritdoc IWeightedPool
    function getWeightedPoolImmutableData() external view returns (WeightedPoolImmutableData memory data) {
        data.tokens = _vault.getPoolTokens(address(this));
        (data.decimalScalingFactors, ) = _vault.getPoolTokenRates(address(this));
        data.normalizedWeights = _getNormalizedWeights();
    }
}
