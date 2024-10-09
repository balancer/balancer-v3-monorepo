// SPDX-License-Identifier: LicenseRef-Gyro-1.0
// for information on licensing please see the README in the GitHub repository
// <https://github.com/gyrostable/concentrated-lps>.

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { ISwapFeePercentageBounds } from "@balancer-labs/v3-interfaces/contracts/vault/ISwapFeePercentageBounds.sol";
import {
    IUnbalancedLiquidityInvariantRatioBounds
} from "@balancer-labs/v3-interfaces/contracts/vault/IUnbalancedLiquidityInvariantRatioBounds.sol";
import { BalancerPoolToken } from "@balancer-labs/v3-vault/contracts/BalancerPoolToken.sol";
import { PoolSwapParams, Rounding, SwapKind } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import "./lib/GyroPoolMath.sol";
import "./lib/Gyro2CLPMath.sol";

contract Gyro2CLPPool is IBasePool, BalancerPoolToken {
    using FixedPoint for uint256;

    uint256 private immutable _sqrtAlpha;
    uint256 private immutable _sqrtBeta;

    bytes32 private constant _POOL_TYPE = "2CLP";

    struct GyroParams {
        string name;
        string symbol;
        uint256 sqrtAlpha; // A: Should already be upscaled
        uint256 sqrtBeta; // A: Should already be upscaled. Could be passed as an array[](2)
    }

    error SqrtParamsWrong();
    error SupportsOnlyTwoTokens();
    error NotImplemented();

    constructor(GyroParams memory params, IVault vault) BalancerPoolToken(vault, params.name, params.symbol) {
        if (params.sqrtAlpha >= params.sqrtBeta) {
            revert SqrtParamsWrong();
        }

        _sqrtAlpha = params.sqrtAlpha;
        _sqrtBeta = params.sqrtBeta;
    }

    /// @inheritdoc IBasePool
    function computeInvariant(uint256[] memory balancesLiveScaled18, Rounding rounding) public view returns (uint256) {
        uint256[2] memory sqrtParams = _sqrtParameters();

        return Gyro2CLPMath._calculateInvariant(balancesLiveScaled18, sqrtParams[0], sqrtParams[1], rounding);
    }

    /// @inheritdoc IBasePool
    function computeBalance(
        uint256[] memory balancesLiveScaled18,
        uint256 tokenInIndex,
        uint256 invariantRatio
    ) external view returns (uint256 newBalance) {
        /**********************************************************************************************
        // Gyro invariant formula is:
        //                                    Lˆ2 = (x + a)(y + b)
        // where:
        //   a = L / _sqrtBeta
        //   b = L * _sqrtAlpha
        //
        // In computeBalance, we want to know what's the new balance of a token, given that invariant
        // changed and the other token balance didn't change. To calculate that for "x", we use:
        //
        //            (L*Lratio)ˆ2 = (newX + (L*Lratio) / _sqrtBeta)(y + (L*Lratio) * _sqrtAlpha)
        //
        // To simplify, let's rename a few terms:
        //
        //                                       squareNewInv = (newX + a)(y + b)
        //
        // Isolating newX:                       newX = (squareNewInv/(y + b)) - a
        // For newY:                             newY = (squareNewInv/(x + a)) - b
        **********************************************************************************************/

        uint256[2] memory sqrtParams = _sqrtParameters();
        uint256 invariant = Gyro2CLPMath._calculateInvariant(
            balancesLiveScaled18,
            sqrtParams[0],
            sqrtParams[1],
            Rounding.ROUND_UP
        );
        // New invariant
        invariant = invariant.mulUp(invariantRatio);
        uint256 squareNewInv = invariant * invariant;
        // L / sqrt(beta)
        uint256 a = invariant.divUp(sqrtParams[1]);
        // L * sqrt(alpha)
        uint256 b = invariant.mulUp(sqrtParams[0]);

        if (tokenInIndex == 0) {
            // if newBalance = newX
            newBalance = squareNewInv.divUpRaw(b + balancesLiveScaled18[1]) - a;
        } else {
            // if newBalance = newY
            newBalance = squareNewInv.divUpRaw(a + balancesLiveScaled18[0]) - b;
        }
    }

    /// @inheritdoc IBasePool
    function onSwap(PoolSwapParams calldata request) public view onlyVault returns (uint256) {
        bool tokenInIsToken0 = request.indexIn == 0;
        uint256 balanceTokenInScaled18 = request.balancesScaled18[request.indexIn];
        uint256 balanceTokenOutScaled18 = request.balancesScaled18[request.indexOut];

        // All the calculations in one function to avoid Error Stack Too Deep
        (, uint256 virtualParamIn, uint256 virtualParamOut) = _calculateCurrentValues(
            balanceTokenInScaled18,
            balanceTokenOutScaled18,
            tokenInIsToken0,
            request.kind == SwapKind.EXACT_IN ? Rounding.ROUND_DOWN : Rounding.ROUND_UP
        );

        if (request.kind == SwapKind.EXACT_IN) {
            uint256 amountOutScaled18 = Gyro2CLPMath._calcOutGivenIn(
                balanceTokenInScaled18,
                balanceTokenOutScaled18,
                request.amountGivenScaled18,
                virtualParamIn,
                virtualParamOut
            );

            return amountOutScaled18;
        } else {
            uint256 amountInScaled18 = Gyro2CLPMath._calcInGivenOut(
                balanceTokenInScaled18,
                balanceTokenOutScaled18,
                request.amountGivenScaled18,
                virtualParamIn,
                virtualParamOut
            );

            // Fees are added after scaling happens, to reduce the complexity of the rounding direction analysis.
            return amountInScaled18;
        }
    }

    function _sqrtParameters() internal view virtual returns (uint256[2] memory virtualParameters) {
        virtualParameters[0] = _sqrtParameters(true);
        virtualParameters[1] = _sqrtParameters(false);
        return virtualParameters;
    }

    function _sqrtParameters(bool parameter0) internal view virtual returns (uint256) {
        return parameter0 ? _sqrtAlpha : _sqrtBeta;
    }

    function _getVirtualParameters(
        uint256[2] memory sqrtParams,
        uint256 invariant
    ) internal view virtual returns (uint256[2] memory virtualParameters) {
        virtualParameters[0] = _virtualParameters(true, sqrtParams[1], invariant);
        virtualParameters[1] = _virtualParameters(false, sqrtParams[0], invariant);
        return virtualParameters;
    }

    function _virtualParameters(
        bool parameter0,
        uint256 sqrtParam,
        uint256 invariant
    ) internal view virtual returns (uint256) {
        return
            parameter0
                ? (Gyro2CLPMath._calculateVirtualParameter0(invariant, sqrtParam))
                : (Gyro2CLPMath._calculateVirtualParameter1(invariant, sqrtParam));
    }

    function _calculateCurrentValues(
        uint256 balanceTokenInScaled18,
        uint256 balanceTokenOutScaled18,
        bool tokenInIsToken0,
        Rounding rounding
    ) internal view returns (uint256 currentInvariant, uint256 virtualParamIn, uint256 virtualParamOut) {
        uint256[] memory balances = new uint256[](2);
        balances[0] = tokenInIsToken0 ? balanceTokenInScaled18 : balanceTokenOutScaled18;
        balances[1] = tokenInIsToken0 ? balanceTokenOutScaled18 : balanceTokenInScaled18;

        uint256[2] memory sqrtParams = _sqrtParameters();

        currentInvariant = Gyro2CLPMath._calculateInvariant(balances, sqrtParams[0], sqrtParams[1], rounding);

        uint256[2] memory virtualParam = _getVirtualParameters(sqrtParams, currentInvariant);

        virtualParamIn = tokenInIsToken0 ? virtualParam[0] : virtualParam[1];
        virtualParamOut = tokenInIsToken0 ? virtualParam[1] : virtualParam[0];
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
