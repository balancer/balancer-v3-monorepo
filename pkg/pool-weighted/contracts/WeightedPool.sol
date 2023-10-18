// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { BasePoolMath } from "@balancer-labs/v3-pool-utils/contracts/lib/BasePoolMath.sol";
import { BasePool } from "@balancer-labs/v3-pool-utils/contracts/BasePool.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { WeightedMath } from "@balancer-labs/v3-solidity-utils/contracts/math/WeightedMath.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { ScalingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ScalingHelpers.sol";

import { IVault, PoolCallbacks } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IWeightedPool } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/IWeightedPool.sol";

/**
 * @dev Basic Weighted Pool with immutable weights.
 */
contract WeightedPool is BasePool, IWeightedPool {
    using FixedPoint for uint256;
    using ScalingHelpers for *;

    uint256 private immutable _totalTokens;

    IERC20 internal immutable _token0;
    IERC20 internal immutable _token1;
    IERC20 internal immutable _token2;
    IERC20 internal immutable _token3;

    // All token balances are normalized to behave as if the token had 18 decimals. We assume a token's decimals will
    // not change throughout its lifetime, and store the corresponding scaling factor for each at construction time.
    // These factors are always greater than or equal to one: tokens with more than 18 decimals are not supported.

    uint256 internal immutable _scalingFactor0;
    uint256 internal immutable _scalingFactor1;
    uint256 internal immutable _scalingFactor2;
    uint256 internal immutable _scalingFactor3;

    uint256 internal immutable _normalizedWeight0;
    uint256 internal immutable _normalizedWeight1;
    uint256 internal immutable _normalizedWeight2;
    uint256 internal immutable _normalizedWeight3;

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
        uint256 bufferPeriodDuration
    ) BasePool(vault, params.name, params.symbol, params.tokens, pauseWindowDuration, bufferPeriodDuration) {
        uint256 numTokens = params.tokens.length;
        InputHelpers.ensureInputLengthMatch(numTokens, params.normalizedWeights.length);

        _totalTokens = numTokens;

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
        _token2 = numTokens > 2 ? params.tokens[2] : IERC20(address(0));
        _token3 = numTokens > 3 ? params.tokens[3] : IERC20(address(0));

        _scalingFactor0 = params.tokens[0].computeScalingFactor();
        _scalingFactor1 = params.tokens[1].computeScalingFactor();
        _scalingFactor2 = numTokens > 2 ? params.tokens[2].computeScalingFactor() : 0;
        _scalingFactor3 = numTokens > 3 ? params.tokens[3].computeScalingFactor() : 0;

        _normalizedWeight0 = params.normalizedWeights[0];
        _normalizedWeight1 = params.normalizedWeights[1];
        _normalizedWeight2 = numTokens > 2 ? params.normalizedWeights[2] : 0;
        _normalizedWeight3 = numTokens > 3 ? params.normalizedWeights[3] : 0;

        vault.registerPool(
            msg.sender,
            params.tokens,
            PoolCallbacks({
                shouldCallAfterAddLiquidity: false,
                shouldCallAfterRemoveLiquidity: false,
                shouldCallAfterSwap: false
            })
        );
    }

    function _getNormalizedWeight(IERC20 token) internal view virtual returns (uint256) {
        // prettier-ignore
        if (token == _token0) { return _normalizedWeight0; }
        else if (token == _token1) { return _normalizedWeight1; }
        else if (token == _token2) { return _normalizedWeight2; }
        else if (token == _token3) { return _normalizedWeight3; }
        else {
            revert IVaultErrors.InvalidToken();
        }
    }

    function _getNormalizedWeights() internal view virtual returns (uint256[] memory) {
        // solhint-disable
        uint256 totalTokens = _getTotalTokens();
        uint256[] memory normalizedWeights = new uint256[](totalTokens);

        normalizedWeights[0] = _normalizedWeight0;
        normalizedWeights[1] = _normalizedWeight1;
        if (totalTokens > 2) { normalizedWeights[2] = _normalizedWeight2; } else { return normalizedWeights; }
        if (totalTokens > 3) { normalizedWeights[3] = _normalizedWeight3; } else { return normalizedWeights; }

        return normalizedWeights;
    }

    function _getMaxTokens() internal pure virtual override returns (uint256) {
        return 2;
    }

    function _getTotalTokens() internal view virtual override returns (uint256) {
        return _totalTokens;
    }

    /**
     * @dev Returns the scaling factor for one of the Pool's tokens. Reverts if `token` is not a token registered by the
     * Pool.
     */
    function _scalingFactor(IERC20 token) internal view virtual override returns (uint256) {
        // prettier-ignore
        if (token == _token0) { return _getScalingFactor0(); }
        else if (token == _token1) { return _getScalingFactor1(); }
        else if (token == _token2) { return _getScalingFactor2(); }
        else if (token == _token3) { return _getScalingFactor3(); }
        else {
            revert IVaultErrors.InvalidToken();
        }
    }

    function _scalingFactors() internal view virtual override returns (uint256[] memory) {
        uint256 totalTokens = _getTotalTokens();
        uint256[] memory scalingFactors = new uint256[](totalTokens);

        // prettier-ignore
        {
            scalingFactors[0] = _getScalingFactor0();
            scalingFactors[1] = _getScalingFactor1();
            if (totalTokens > 2) { scalingFactors[2] = _getScalingFactor2(); } else { return scalingFactors; }
            if (totalTokens > 3) { scalingFactors[3] = _getScalingFactor3(); } else { return scalingFactors; }
        }

        return scalingFactors;
    }

    function _getScalingFactor0() internal view returns (uint256) {
        return _scalingFactor0;
    }

    function _getScalingFactor1() internal view returns (uint256) {
        return _scalingFactor1;
    }

    function _getScalingFactor2() internal view returns (uint256) {
        return _scalingFactor2;
    }

    function _getScalingFactor3() internal view returns (uint256) {
        return _scalingFactor3;
    }

    /// @dev Returns the current value of the invariant.
    function getInvariant() public view returns (uint256) {
        (, uint256[] memory balances) = _vault.getPoolTokens(address(this));

        // Since the Pool hooks always work with upscaled balances, we manually
        // upscale here for consistency
        balances.upscaleArray(_scalingFactors());

        uint256[] memory normalizedWeights = _getNormalizedWeights();
        return WeightedMath.calculateInvariant(normalizedWeights, balances);
    }

    function getNormalizedWeights() external view returns (uint256[] memory) {
        return _getNormalizedWeights();
    }

    /// Swap

    /// @inheritdoc IBasePool
    function onSwap(IBasePool.SwapParams memory request) public view onlyVault returns (uint256) {
        uint256 scalingFactorTokenIn = _scalingFactor(request.tokenIn);
        uint256 scalingFactorTokenOut = _scalingFactor(request.tokenOut);

        uint256 balanceTokenIn = request.balances[request.indexIn].upscale(scalingFactorTokenIn);
        uint256 balanceTokenOut = request.balances[request.indexOut].upscale(scalingFactorTokenOut);

        if (request.kind == IVault.SwapKind.GIVEN_IN) {
            uint256 amountOut = WeightedMath.calcOutGivenIn(
                balanceTokenIn,
                _getNormalizedWeight(request.tokenIn),
                balanceTokenOut,
                _getNormalizedWeight(request.tokenOut),
                // All token amounts are upscaled.
                request.amountGiven.upscale(scalingFactorTokenIn)
            );

            // amountOut tokens are exiting the Pool, so we round down.
            return amountOut.downscaleDown(scalingFactorTokenOut);
        } else {
            // All token amounts are upscaled.

            uint256 amountIn = WeightedMath.calcInGivenOut(
                balanceTokenIn,
                _getNormalizedWeight(request.tokenIn),
                balanceTokenOut,
                _getNormalizedWeight(request.tokenOut),
                request.amountGiven.upscale(scalingFactorTokenOut)
            );

            // amountIn tokens are entering the Pool, so we round up.
            amountIn = amountIn.downscaleUp(scalingFactorTokenIn);

            // Fees are added after scaling happens, to reduce the complexity of the rounding direction analysis.
            return amountIn;
        }
    }

    /// @inheritdoc IBasePool
    function onAfterSwap(
        IBasePool.AfterSwapParams calldata params,
        uint256 amountCalculated
    ) external pure override returns (bool success) {
        return params.tokenIn != params.tokenOut && amountCalculated > 0;
    }

    /// Initialize

    /// @inheritdoc IBasePool
    function onInitialize(
        uint256[] memory amountsIn,
        bytes memory
    ) external view onlyVault returns (uint256[] memory, uint256) {
        uint256[] memory scalingFactors = _scalingFactors();
        amountsIn.upscaleArray(scalingFactors);

        uint256[] memory normalizedWeights = _getNormalizedWeights();
        uint256 invariantAfterJoin = WeightedMath.calculateInvariant(normalizedWeights, amountsIn);

        // Set the initial pool tokens amount to the value of the invariant times the number of tokens.
        // This makes pool token supply more consistent in Pools with similar compositions
        // but different number of tokens.
        uint256 bptAmountOut = invariantAfterJoin * amountsIn.length;

        // amountsIn are amounts entering the Pool, so we round up.
        amountsIn.downscaleUpArray(scalingFactors);

        return (amountsIn, bptAmountOut);
    }

    /// @inheritdoc IBasePool
    function onAddLiquidity(
        address,
        uint256[] memory balances,
        uint256[] memory amountsIn,
        uint256 minBptAmountOut,
        AddLiquidityKind kind,
        bytes memory
    ) external view onlyVault returns (uint256[] memory, uint256 bptAmountOut) {
        uint256[] memory scalingFactors = _scalingFactors();
        balances.upscaleArray(scalingFactors);
        amountsIn.upscaleArray(scalingFactors);

        uint256[] memory normalizedWeights = _getNormalizedWeights();

        if (kind == AddLiquidityKind.EXACT_TOKENS_IN_FOR_BPT_OUT) {
            InputHelpers.ensureInputLengthMatch(balances.length, amountsIn.length);

            bptAmountOut = WeightedMath.calcBptOutGivenExactTokensIn(
                balances,
                normalizedWeights,
                amountsIn,
                totalSupply(),
                getSwapFeePercentage()
            );
        } else if (kind == AddLiquidityKind.TOKEN_IN_FOR_EXACT_BPT_OUT) {
            // The token in cannot be specified with these arguments without relying on `userData`.
            // This shall be implemented in the future with explicit arguments.
            revert UnhandledJoinKind();
        } else if (kind == AddLiquidityKind.ALL_TOKENS_IN_FOR_EXACT_BPT_OUT) {
            amountsIn = BasePoolMath.computeProportionalAmountsIn(balances, totalSupply(), minBptAmountOut);
            bptAmountOut = minBptAmountOut;
        } else {
            revert UnhandledJoinKind();
        }

        // amountsIn are amounts entering the Pool, so we round up.
        amountsIn.downscaleUpArray(scalingFactors);

        return (amountsIn, bptAmountOut);
    }

    /// @inheritdoc IBasePool
    function onRemoveLiquidity(
        address,
        uint256[] memory balances,
        uint256[] memory minAmountsOut,
        uint256 maxBptAmountIn,
        RemoveLiquidityKind kind,
        bytes memory
    ) external view onlyVault returns (uint256[] memory amountsOut, uint256 bptAmountIn) {
        uint256[] memory scalingFactors = _scalingFactors();
        balances.upscaleArray(scalingFactors);
        minAmountsOut.upscaleArray(scalingFactors);

        uint256[] memory normalizedWeights = _getNormalizedWeights();

        if (kind == RemoveLiquidityKind.EXACT_BPT_IN_FOR_ONE_TOKEN_OUT) {
            // The token in cannot be specified with these arguments without relying on `userData`.
            // This shall be implemented in the future with explicit arguments.
            revert UnhandledExitKind();

        } else if (kind == RemoveLiquidityKind.EXACT_BPT_IN_FOR_TOKENS_OUT) {
            amountsOut = BasePoolMath.computeProportionalAmountsOut(balances, totalSupply(), maxBptAmountIn);
            bptAmountIn = maxBptAmountIn;
        } else if (kind == RemoveLiquidityKind.BPT_IN_FOR_EXACT_TOKENS_OUT) {
            InputHelpers.ensureInputLengthMatch(minAmountsOut.length, balances.length);

            // This is an exceptional situation in which the fee is charged on a token out instead of a token in.
            bptAmountIn = WeightedMath.calcBptInGivenExactTokensOut(
                balances,
                normalizedWeights,
                minAmountsOut,
                totalSupply(),
                getSwapFeePercentage()
            );
        } else {
            revert UnhandledExitKind();
        }
        // amountsOut are amounts exiting the Pool, so we round down.
        amountsOut.downscaleDownArray(scalingFactors);

        return (amountsOut, bptAmountIn);
    }
}
