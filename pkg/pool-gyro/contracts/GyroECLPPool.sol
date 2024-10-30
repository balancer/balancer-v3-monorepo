// SPDX-License-Identifier: LicenseRef-Gyro-1.0
// for information on licensing please see the README in the GitHub repository
// <https://github.com/gyrostable/concentrated-lps>.

pragma solidity ^0.8.24;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IGyroECLPPool } from "@balancer-labs/v3-interfaces/contracts/pool-gyro/IGyroECLPPool.sol";
import { ISwapFeePercentageBounds } from "@balancer-labs/v3-interfaces/contracts/vault/ISwapFeePercentageBounds.sol";
import {
    IUnbalancedLiquidityInvariantRatioBounds
} from "@balancer-labs/v3-interfaces/contracts/vault/IUnbalancedLiquidityInvariantRatioBounds.sol";
import { PoolSwapParams, Rounding, SwapKind } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { BalancerPoolToken } from "@balancer-labs/v3-vault/contracts/BalancerPoolToken.sol";

import { GyroECLPMath } from "./lib/GyroECLPMath.sol";

contract GyroECLPPool is IGyroECLPPool, BalancerPoolToken {
    using FixedPoint for uint256;
    using SafeCast for *;

    /// @dev Parameters of the ECLP pool
    int256 internal immutable _paramsAlpha;
    int256 internal immutable _paramsBeta;
    int256 internal immutable _paramsC;
    int256 internal immutable _paramsS;
    int256 internal immutable _paramsLambda;
    int256 internal immutable _tauAlphaX;
    int256 internal immutable _tauAlphaY;
    int256 internal immutable _tauBetaX;
    int256 internal immutable _tauBetaY;
    int256 internal immutable _u;
    int256 internal immutable _v;
    int256 internal immutable _w;
    int256 internal immutable _z;
    int256 internal immutable _dSq;
    bytes32 private constant _POOL_TYPE = "ECLP";

    constructor(GyroECLPPoolParams memory params, IVault vault) BalancerPoolToken(vault, params.name, params.symbol) {
        GyroECLPMath.validateParams(params.eclpParams);
        emit ECLPParamsValidated(true);

        GyroECLPMath.validateDerivedParamsLimits(params.eclpParams, params.derivedEclpParams);
        emit ECLPDerivedParamsValidated(true);

        (_paramsAlpha, _paramsBeta, _paramsC, _paramsS, _paramsLambda) = (
            params.eclpParams.alpha,
            params.eclpParams.beta,
            params.eclpParams.c,
            params.eclpParams.s,
            params.eclpParams.lambda
        );

        (_tauAlphaX, _tauAlphaY, _tauBetaX, _tauBetaY, _u, _v, _w, _z, _dSq) = (
            params.derivedEclpParams.tauAlpha.x,
            params.derivedEclpParams.tauAlpha.y,
            params.derivedEclpParams.tauBeta.x,
            params.derivedEclpParams.tauBeta.y,
            params.derivedEclpParams.u,
            params.derivedEclpParams.v,
            params.derivedEclpParams.w,
            params.derivedEclpParams.z,
            params.derivedEclpParams.dSq
        );
    }

    /// @inheritdoc IBasePool
    function computeInvariant(
        uint256[] memory balancesLiveScaled18,
        Rounding rounding
    ) external view returns (uint256) {
        (EclpParams memory eclpParams, DerivedEclpParams memory derivedECLPParams) = _reconstructECLPParams();

        (int256 currentInvariant, int256 invErr) = GyroECLPMath.calculateInvariantWithError(
            balancesLiveScaled18,
            eclpParams,
            derivedECLPParams
        );

        if (rounding == Rounding.ROUND_DOWN) {
            return currentInvariant.toUint256();
        } else {
            return (currentInvariant + 20 * invErr).toUint256();
        }
    }

    /// @inheritdoc IBasePool
    function computeBalance(
        uint256[] memory balancesLiveScaled18,
        uint256 tokenInIndex,
        uint256 invariantRatio
    ) external view returns (uint256 newBalance) {
        (EclpParams memory eclpParams, DerivedEclpParams memory derivedECLPParams) = _reconstructECLPParams();

        Vector2 memory invariant;
        {
            (int256 currentInvariant, int256 invErr) = GyroECLPMath.calculateInvariantWithError(
                balancesLiveScaled18,
                eclpParams,
                derivedECLPParams
            );

            // invariant = overestimate in x-component, underestimate in y-component.
            invariant = Vector2(
                (currentInvariant + 2 * invErr).toUint256().mulUp(invariantRatio).toInt256(),
                currentInvariant.toUint256().mulUp(invariantRatio).toInt256()
            );
        }

        if (tokenInIndex == 0) {
            return
                GyroECLPMath
                    .calcXGivenY(balancesLiveScaled18[1].toInt256(), eclpParams, derivedECLPParams, invariant)
                    .toUint256();
        } else {
            return
                GyroECLPMath
                    .calcYGivenX(balancesLiveScaled18[0].toInt256(), eclpParams, derivedECLPParams, invariant)
                    .toUint256();
        }
    }

    /// @inheritdoc IBasePool
    function onSwap(PoolSwapParams memory request) external view onlyVault returns (uint256) {
        bool tokenInIsToken0 = request.indexIn == 0;

        (EclpParams memory eclpParams, DerivedEclpParams memory derivedECLPParams) = _reconstructECLPParams();
        Vector2 memory invariant;
        {
            (int256 currentInvariant, int256 invErr) = GyroECLPMath.calculateInvariantWithError(
                request.balancesScaled18,
                eclpParams,
                derivedECLPParams
            );
            // invariant = overestimate in x-component, underestimate in y-component
            // No overflow in `+` due to constraints to the different values enforced in GyroECLPMath.
            invariant = Vector2(currentInvariant + 2 * invErr, currentInvariant);
        }

        if (request.kind == SwapKind.EXACT_IN) {
            uint256 amountOutScaled18 = GyroECLPMath.calcOutGivenIn(
                request.balancesScaled18,
                request.amountGivenScaled18,
                tokenInIsToken0,
                eclpParams,
                derivedECLPParams,
                invariant
            );

            return amountOutScaled18;
        } else {
            uint256 amountInScaled18 = GyroECLPMath.calcInGivenOut(
                request.balancesScaled18,
                request.amountGivenScaled18,
                tokenInIsToken0,
                eclpParams,
                derivedECLPParams,
                invariant
            );

            // Fees are added after scaling happens, to reduce the complexity of the rounding direction analysis.
            return amountInScaled18;
        }
    }

    /** @dev reconstructs ECLP params structs from immutable arrays */
    function _reconstructECLPParams() private view returns (EclpParams memory params, DerivedEclpParams memory d) {
        (params.alpha, params.beta, params.c, params.s, params.lambda) = (
            _paramsAlpha,
            _paramsBeta,
            _paramsC,
            _paramsS,
            _paramsLambda
        );
        (d.tauAlpha.x, d.tauAlpha.y, d.tauBeta.x, d.tauBeta.y) = (_tauAlphaX, _tauAlphaY, _tauBetaX, _tauBetaY);
        (d.u, d.v, d.w, d.z, d.dSq) = (_u, _v, _w, _z, _dSq);
    }

    function getECLPParams() external view returns (EclpParams memory params, DerivedEclpParams memory d) {
        return _reconstructECLPParams();
    }

    /// @inheritdoc ISwapFeePercentageBounds
    function getMinimumSwapFeePercentage() external pure returns (uint256) {
        return 0;
    }

    /// @inheritdoc ISwapFeePercentageBounds
    function getMaximumSwapFeePercentage() external pure returns (uint256) {
        return 1e18;
    }

    /// @inheritdoc IUnbalancedLiquidityInvariantRatioBounds
    function getMinimumInvariantRatio() external pure returns (uint256) {
        return 0;
    }

    /// @inheritdoc IUnbalancedLiquidityInvariantRatioBounds
    function getMaximumInvariantRatio() external pure returns (uint256) {
        return type(uint256).max;
    }
}
