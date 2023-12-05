// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// solhint-disable-next-line max-line-length
import { IVault, PoolCallbacks, LiquidityManagement } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IVault, PoolCallbacks } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";

import { BasePoolMath } from "@balancer-labs/v3-solidity-utils/contracts/math/BasePoolMath.sol";
import { BasePool } from "@balancer-labs/v3-vault/contracts/BasePool.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { WeightedMath } from "@balancer-labs/v3-solidity-utils/contracts/math/WeightedMath.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { ScalingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ScalingHelpers.sol";
import { PoolConfigLib } from "@balancer-labs/v3-vault/contracts/lib/PoolConfigLib.sol";

/// @notice Basic Weighted Pool with immutable weights.
contract WeightedPool is BasePool {
    using FixedPoint for uint256;
    using ScalingHelpers for *;

    uint256 private immutable _totalTokens;

    IERC20 internal immutable _token0;
    IERC20 internal immutable _token1;
    IERC20 internal immutable _token2;
    IERC20 internal immutable _token3;

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

    /// @dev Indicates that one of the pool tokens' weight is below the minimum allowed.
    error MinWeight();

    /// @dev Indicates that the sum of the pool tokens' weights is not FP 1.
    error NormalizedWeightInvariant();

    constructor(NewPoolParams memory params, IVault vault) BasePool(vault, params.name, params.symbol) {
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

        _normalizedWeight0 = params.normalizedWeights[0];
        _normalizedWeight1 = params.normalizedWeights[1];
        _normalizedWeight2 = numTokens > 2 ? params.normalizedWeights[2] : 0;
        _normalizedWeight3 = numTokens > 3 ? params.normalizedWeights[3] : 0;
    }

    function _getNormalizedWeight(IERC20 token) internal view virtual returns (uint256) {
        // prettier-ignore
        if (token == _token0) { return _normalizedWeight0; }
        else if (token == _token1) { return _normalizedWeight1; }
        else if (token == _token2) { return _normalizedWeight2; }
        else if (token == _token3) { return _normalizedWeight3; }
        else {
            revert IVault.InvalidToken();
        }
    }

    function _getNormalizedWeights() internal view virtual returns (uint256[] memory) {
        // solhint-disable
        uint256 totalTokens = _getTotalTokens();
        uint256[] memory normalizedWeights = new uint256[](totalTokens);

        // prettier-ignore
        normalizedWeights[0] = _normalizedWeight0;
        normalizedWeights[1] = _normalizedWeight1;
        if (totalTokens > 2) {
            normalizedWeights[2] = _normalizedWeight2;
        } else {
            return normalizedWeights;
        }
        if (totalTokens > 3) {
            normalizedWeights[3] = _normalizedWeight3;
        } else {
            return normalizedWeights;
        }

        return normalizedWeights;
    }

    function _getTotalTokens() internal view virtual override returns (uint256) {
        return _totalTokens;
    }

    /**
     * @dev Get the current invariant.
     * @return The current value of the invariant
     */
    function getInvariant(uint256[] memory balancesLiveScaled18) public view returns (uint256) {
        return WeightedMath.calculateInvariant(_getNormalizedWeights(), balancesLiveScaled18);
    }

    function calcBalance(
        uint256[] memory balances,
        uint256 tokenInIndex,
        uint256 invariantRatio
    ) external view returns (uint256 newBalance) {
        return
            WeightedMath.calculatetBalanceOutGivenInvariant(
                balances[tokenInIndex],
                _getNormalizedWeights()[tokenInIndex],
                invariantRatio
            );
    }

    /**
     * @dev Get the normalized weights.
     * @return An array of normalized weights, corresponding to the pool tokens
     */
    function getNormalizedWeights() external view returns (uint256[] memory) {
        return _getNormalizedWeights();
    }

    /***************************************************************************
                               Pool Initialization
    ***************************************************************************/

    /// @inheritdoc IBasePool
    function onInitialize(
        uint256[] memory exactAmountsInScaled18,
        bytes memory
    ) external view onlyVault returns (uint256) {
        uint256[] memory normalizedWeights = _getNormalizedWeights();
        uint256 invariantAfterJoin = WeightedMath.calculateInvariant(normalizedWeights, exactAmountsInScaled18);

        // Set the initial pool tokens amount to the value of the invariant times the number of tokens.
        // This makes pool token supply more consistent in Pools with similar compositions
        // but different number of tokens.
        uint256 bptAmountOut = invariantAfterJoin * exactAmountsInScaled18.length;

        return bptAmountOut;
    }

    /***************************************************************************
                                       Swaps
    ***************************************************************************/

    /// @inheritdoc IBasePool
    function onSwap(IBasePool.SwapParams memory request) public view onlyVault returns (uint256) {
        uint256 balanceTokenInScaled18 = request.balancesScaled18[request.indexIn];
        uint256 balanceTokenOutScaled18 = request.balancesScaled18[request.indexOut];

        if (request.kind == IVault.SwapKind.GIVEN_IN) {
            uint256 amountOutScaled18 = WeightedMath.calcOutGivenIn(
                balanceTokenInScaled18,
                _getNormalizedWeight(request.tokenIn),
                balanceTokenOutScaled18,
                _getNormalizedWeight(request.tokenOut),
                request.amountGivenScaled18
            );

            return amountOutScaled18;
        } else {
            uint256 amountInScaled18 = WeightedMath.calcInGivenOut(
                balanceTokenInScaled18,
                _getNormalizedWeight(request.tokenIn),
                balanceTokenOutScaled18,
                _getNormalizedWeight(request.tokenOut),
                request.amountGivenScaled18
            );

            // Fees are added after scaling happens, to reduce the complexity of the rounding direction analysis.
            return amountInScaled18;
        }
    }

    /// @inheritdoc IBasePool
    function onAfterSwap(
        IBasePool.AfterSwapParams calldata params,
        uint256 amountCalculatedScaled18
    ) external pure override returns (bool success) {
        // TODO: review the need of this.
        return params.tokenIn != params.tokenOut && amountCalculatedScaled18 > 0;
    }

    /***************************************************************************
                                   Add Liquidity
    ***************************************************************************/

    /***************************************************************************
                                 Remove Liquidity
    ***************************************************************************/

    function onRemoveLiquiditySingleTokenExactIn(
        address,
        uint256 tokenOutIndex,
        uint256 exactBptAmountIn,
        uint256[] memory balancesScaled18
    ) external view override returns (uint256 amountOut) {
        uint256[] memory normalizedWeights = _getNormalizedWeights();

        return
            WeightedMath.calcTokenOutGivenExactBptIn(
                balancesScaled18[tokenOutIndex],
                normalizedWeights[tokenOutIndex],
                exactBptAmountIn,
                totalSupply(),
                getSwapFeePercentage()
            );
    }
}
