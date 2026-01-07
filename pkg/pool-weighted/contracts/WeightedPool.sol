// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { ISwapFeePercentageBounds } from "@balancer-labs/v3-interfaces/contracts/vault/ISwapFeePercentageBounds.sol";
import {
    IUnbalancedLiquidityInvariantRatioBounds
} from "@balancer-labs/v3-interfaces/contracts/vault/IUnbalancedLiquidityInvariantRatioBounds.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import {
    IWeightedPool,
    WeightedPoolDynamicData,
    WeightedPoolImmutableData
} from "@balancer-labs/v3-interfaces/contracts/pool-weighted/IWeightedPool.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { MinTokenBalanceLib } from "@balancer-labs/v3-vault/contracts/lib/MinTokenBalanceLib.sol";
import { WeightedMath } from "@balancer-labs/v3-solidity-utils/contracts/math/WeightedMath.sol";
import { BalancerPoolToken } from "@balancer-labs/v3-vault/contracts/BalancerPoolToken.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { Version } from "@balancer-labs/v3-solidity-utils/contracts/helpers/Version.sol";
import { PoolInfo } from "@balancer-labs/v3-pool-utils/contracts/PoolInfo.sol";

/**
 * @notice Standard Balancer Weighted Pool, with fixed weights.
 * @dev Weighted Pools are designed for uncorrelated assets, and use `WeightedMath` (from Balancer v1 and v2)
 * to compute the price curve.
 *
 * There can be up to 8 tokens in a weighted pool (same as v2), and the normalized weights (expressed as 18-decimal
 * fixed point numbers), must sum to FixedPoint.ONE. Weights cannot be changed after deployment.
 *
 * The swap fee percentage is bounded by minimum and maximum values (same as were used in v2).
 */
contract WeightedPool is IWeightedPool, BalancerPoolToken, PoolInfo, Version {
    /// @dev Struct with data for deploying a new WeightedPool. `normalizedWeights` length must match `numTokens`.
    struct NewPoolParams {
        string name;
        string symbol;
        uint256 numTokens;
        uint256[] normalizedWeights;
        string version;
        uint256[] minTokenBalances;
    }

    // Fees are 18-decimal, fixed point values, which will be stored in the Vault using 24 bits.
    // This means they have 0.00001% resolution (i.e., any non-zero bits < 1e11 will cause precision loss).
    // Minimum values help make the math well-behaved (i.e., the swap fee should overwhelm any rounding error).
    // Maximum values protect users by preventing permissioned actors from setting excessively high swap fees.
    uint256 private constant _MIN_SWAP_FEE_PERCENTAGE = 0.001e16; // 0.001%
    uint256 private constant _MAX_SWAP_FEE_PERCENTAGE = 10e16; // 10%

    // A minimum normalized weight imposes a maximum weight ratio. We need this due to limitations in the
    // implementation of the fixed point power function, as these ratios are often exponents.
    uint256 internal constant _MIN_WEIGHT = 1e16; // 1%

    uint256 private immutable _totalTokens;

    uint256 internal immutable _normalizedWeight0;
    uint256 internal immutable _normalizedWeight1;
    uint256 internal immutable _normalizedWeight2;
    uint256 internal immutable _normalizedWeight3;
    uint256 internal immutable _normalizedWeight4;
    uint256 internal immutable _normalizedWeight5;
    uint256 internal immutable _normalizedWeight6;
    uint256 internal immutable _normalizedWeight7;

    // The minimum balances for each token, as 18-decimal fixed point values.
    uint256 private immutable _minBalance0;
    uint256 private immutable _minBalance1;
    uint256 private immutable _minBalance2;
    uint256 private immutable _minBalance3;
    uint256 private immutable _minBalance4;
    uint256 private immutable _minBalance5;
    uint256 private immutable _minBalance6;
    uint256 private immutable _minBalance7;

    /**
     * @notice `getRate` from `IRateProvider` was called on a Weighted Pool.
     * @dev It is not safe to nest Weighted Pools as WITH_RATE tokens in other pools, where they function as their own
     * rate provider. The default `getRate` implementation from `BalancerPoolToken` computes the BPT rate using the
     * invariant, which has a non-trivial (and non-linear) error. Without the ability to specify a rounding direction,
     * the rate could be manipulable.
     *
     * It is fine to nest Weighted Pools as STANDARD tokens, or to use them with external rate providers that are
     * stable and have at most 1 wei of rounding error (e.g., oracle-based).
     */
    error WeightedPoolBptRateUnsupported();

    constructor(
        NewPoolParams memory params,
        IVault vault
    ) BalancerPoolToken(vault, params.name, params.symbol) PoolInfo(vault) Version(params.version) {
        _totalTokens = params.numTokens;
        InputHelpers.ensureInputLengthMatch(_totalTokens, params.normalizedWeights.length);

        // Ensure each normalized weight is above the minimum. Also validate and set the minimum balances.
        uint256 normalizedSum = 0;
        for (uint8 i = 0; i < _totalTokens; ++i) {
            uint256 normalizedWeight = params.normalizedWeights[i];

            if (normalizedWeight < _MIN_WEIGHT) {
                revert MinWeight();
            }
            normalizedSum = normalizedSum + normalizedWeight;

            uint256 minTokenBalance = params.minTokenBalances[i];
            if (minTokenBalance < MinTokenBalanceLib.ABSOLUTE_MIN_TOKEN_BALANCE) {
                revert MinTokenBalanceLib.InvalidMinTokenBalance();
            }

            // prettier-ignore
            {
                if (i == 0) { _normalizedWeight0 = normalizedWeight; _minBalance0 = minTokenBalance; }
                else if (i == 1) { _normalizedWeight1 = normalizedWeight; _minBalance1 = minTokenBalance; }
                else if (i == 2) { _normalizedWeight2 = normalizedWeight; _minBalance2 = minTokenBalance; }
                else if (i == 3) { _normalizedWeight3 = normalizedWeight; _minBalance3 = minTokenBalance; }
                else if (i == 4) { _normalizedWeight4 = normalizedWeight; _minBalance4 = minTokenBalance; }
                else if (i == 5) { _normalizedWeight5 = normalizedWeight; _minBalance5 = minTokenBalance; }
                else if (i == 6) { _normalizedWeight6 = normalizedWeight; _minBalance6 = minTokenBalance; }
                else if (i == 7) { _normalizedWeight7 = normalizedWeight; _minBalance7 = minTokenBalance; }
            }
        }

        // Ensure that the normalized weights sum to ONE.
        if (normalizedSum != FixedPoint.ONE) {
            revert NormalizedWeightInvariant();
        }
    }

    /// @inheritdoc IBasePool
    function computeInvariant(
        uint256[] memory balancesLiveScaled18,
        Rounding rounding
    ) public view virtual returns (uint256) {
        _ensureMinTokenBalances(balancesLiveScaled18);

        function(uint256[] memory, uint256[] memory) internal pure returns (uint256) _upOrDown = rounding ==
            Rounding.ROUND_UP
            ? WeightedMath.computeInvariantUp
            : WeightedMath.computeInvariantDown;

        return _upOrDown(_getNormalizedWeights(), balancesLiveScaled18);
    }

    /// @inheritdoc IBasePool
    function computeBalance(
        uint256[] memory balancesLiveScaled18,
        uint256 tokenInIndex,
        uint256 invariantRatio
    ) external view virtual returns (uint256 newBalance) {
        uint256 originalBalance = balancesLiveScaled18[tokenInIndex];

        newBalance = WeightedMath.computeBalanceOutGivenInvariant(
            originalBalance,
            _getNormalizedWeight(tokenInIndex),
            invariantRatio
        );

        if (originalBalance <= newBalance) {
            // Add operation: modified token is lowest before.
            _ensureMinimumBalance(tokenInIndex, originalBalance);
        } else {
            // Remove operation: modified token is lowest after.
            _ensureMinimumBalance(tokenInIndex, newBalance);
        }
    }

    /// @inheritdoc IBasePool
    function onSwap(PoolSwapParams memory request) public view virtual returns (uint256 calculatedAmountScaled18) {
        uint256 balanceTokenInScaled18 = request.balancesScaled18[request.indexIn];
        uint256 balanceTokenOutScaled18 = request.balancesScaled18[request.indexOut];
        uint256 amountOutScaled18;

        // Check at the beginning, in case a proportional remove (which doesn't go through the pool), dropped a balance
        // below the minimum.
        _ensureMinimumBalance(request.indexIn, balanceTokenInScaled18);

        if (request.kind == SwapKind.EXACT_IN) {
            calculatedAmountScaled18 = WeightedMath.computeOutGivenExactIn(
                balanceTokenInScaled18,
                _getNormalizedWeight(request.indexIn),
                balanceTokenOutScaled18,
                _getNormalizedWeight(request.indexOut),
                request.amountGivenScaled18
            );

            amountOutScaled18 = calculatedAmountScaled18;
        } else {
            calculatedAmountScaled18 = WeightedMath.computeInGivenExactOut(
                balanceTokenInScaled18,
                _getNormalizedWeight(request.indexIn),
                balanceTokenOutScaled18,
                _getNormalizedWeight(request.indexOut),
                request.amountGivenScaled18
            );

            amountOutScaled18 = request.amountGivenScaled18;

            // Fees are added after scaling happens, to reduce the complexity of the rounding direction analysis.
        }

        // Check again at the end, to ensure the swap did not drop the token out balance below the minimum.
        _ensureMinimumBalance(request.indexOut, balanceTokenOutScaled18 - amountOutScaled18);
    }

    /// @inheritdoc IWeightedPool
    function getNormalizedWeights() external view returns (uint256[] memory) {
        return _getNormalizedWeights();
    }

    /// @inheritdoc IWeightedPool
    function getMinTokenBalances() external view returns (uint256[] memory minTokenBalances) {
        return _getMinTokenBalances();
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
    function getWeightedPoolDynamicData() external view virtual returns (WeightedPoolDynamicData memory data) {
        data.balancesLiveScaled18 = _vault.getCurrentLiveBalances(address(this));
        (, data.tokenRates) = _vault.getPoolTokenRates(address(this));
        data.staticSwapFeePercentage = _vault.getStaticSwapFeePercentage((address(this)));
        data.totalSupply = totalSupply();

        PoolConfig memory poolConfig = _vault.getPoolConfig(address(this));
        data.isPoolInitialized = poolConfig.isPoolInitialized;
        data.isPoolPaused = poolConfig.isPoolPaused;
        data.isPoolInRecoveryMode = poolConfig.isPoolInRecoveryMode;
    }

    /// @inheritdoc IWeightedPool
    function getWeightedPoolImmutableData() external view virtual returns (WeightedPoolImmutableData memory data) {
        data.tokens = _vault.getPoolTokens(address(this));
        (data.decimalScalingFactors, ) = _vault.getPoolTokenRates(address(this));
        data.normalizedWeights = _getNormalizedWeights();
        data.minTokenBalances = _getMinTokenBalances();
    }

    /// @inheritdoc IRateProvider
    function getRate() public pure override returns (uint256) {
        revert WeightedPoolBptRateUnsupported();
    }

    function _getNormalizedWeights() internal view virtual returns (uint256[] memory normalizedWeights) {
        uint256 totalTokens = _totalTokens;
        normalizedWeights = new uint256[](totalTokens);

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
    }

    function _getNormalizedWeight(uint256 tokenIndex) internal view virtual returns (uint256) {
        // prettier-ignore
        {
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
    }

    function _getMinTokenBalances() internal view returns (uint256[] memory minTokenBalances) {
        IERC20[] memory tokens = _vault.getPoolTokens(address(this));

        uint256 numTokens = tokens.length;
        minTokenBalances = new uint256[](numTokens);

        // prettier-ignore
        {
            minTokenBalances[0] = _minBalance0;
            minTokenBalances[1] = _minBalance1;
            if (numTokens > 2) { minTokenBalances[2] = _minBalance2; } else { return minTokenBalances; }
            if (numTokens > 3) { minTokenBalances[3] = _minBalance3; } else { return minTokenBalances; }
            if (numTokens > 4) { minTokenBalances[4] = _minBalance4; } else { return minTokenBalances; }
            if (numTokens > 5) { minTokenBalances[5] = _minBalance5; } else { return minTokenBalances; }
            if (numTokens > 6) { minTokenBalances[6] = _minBalance6; } else { return minTokenBalances; }
            if (numTokens > 7) { minTokenBalances[7] = _minBalance7; }
        }
    }

    function _ensureMinTokenBalances(uint256[] memory balancesLiveScaled18) internal view {
        uint256 numTokens = balancesLiveScaled18.length;

        if (balancesLiveScaled18[0] < _minBalance0) {
            revert MinTokenBalanceLib.TokenBalanceBelowMin(0, balancesLiveScaled18[0], _minBalance0);
        }
        if (balancesLiveScaled18[1] < _minBalance1) {
            revert MinTokenBalanceLib.TokenBalanceBelowMin(1, balancesLiveScaled18[1], _minBalance1);
        }

        if (numTokens > 2) {
            if (balancesLiveScaled18[2] < _minBalance2) {
                revert MinTokenBalanceLib.TokenBalanceBelowMin(2, balancesLiveScaled18[2], _minBalance2);
            }
        } else {
            return;
        }

        if (numTokens > 3) {
            if (balancesLiveScaled18[3] < _minBalance3) {
                revert MinTokenBalanceLib.TokenBalanceBelowMin(3, balancesLiveScaled18[3], _minBalance3);
            }
        } else {
            return;
        }

        if (numTokens > 4) {
            if (balancesLiveScaled18[4] < _minBalance4) {
                revert MinTokenBalanceLib.TokenBalanceBelowMin(4, balancesLiveScaled18[4], _minBalance4);
            }
        } else {
            return;
        }

        if (numTokens > 5) {
            if (balancesLiveScaled18[5] < _minBalance5) {
                revert MinTokenBalanceLib.TokenBalanceBelowMin(5, balancesLiveScaled18[5], _minBalance5);
            }
        } else {
            return;
        }

        if (numTokens > 6) {
            if (balancesLiveScaled18[6] < _minBalance6) {
                revert MinTokenBalanceLib.TokenBalanceBelowMin(6, balancesLiveScaled18[6], _minBalance6);
            }
        } else {
            return;
        }

        if (numTokens > 7) {
            if (balancesLiveScaled18[7] < _minBalance7) {
                revert MinTokenBalanceLib.TokenBalanceBelowMin(7, balancesLiveScaled18[7], _minBalance7);
            }
        } else {
            return;
        }
    }

    function _ensureMinimumBalance(uint256 tokenIndex, uint256 endingBalanceScaled18) internal view {
        uint256 minimumBalanceScaled18;

        // prettier-ignore
        {
            if (tokenIndex == 0) { minimumBalanceScaled18 = _minBalance0; }
            else if (tokenIndex == 1) { minimumBalanceScaled18 = _minBalance1; }
            else if (tokenIndex == 2) { minimumBalanceScaled18 = _minBalance2; }
            else if (tokenIndex == 3) { minimumBalanceScaled18 = _minBalance3; }
            else if (tokenIndex == 4) { minimumBalanceScaled18 = _minBalance4; }
            else if (tokenIndex == 5) { minimumBalanceScaled18 = _minBalance5; }
            else if (tokenIndex == 6) { minimumBalanceScaled18 = _minBalance6; }
            else { minimumBalanceScaled18 = _minBalance7; }   
        }

        if (endingBalanceScaled18 < minimumBalanceScaled18) {
            revert MinTokenBalanceLib.TokenBalanceBelowMin(tokenIndex, endingBalanceScaled18, minimumBalanceScaled18);
        }
    }
}
