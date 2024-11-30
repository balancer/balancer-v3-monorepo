// SPDX-License-Identifier: LicenseRef-Gyro-1.0
// for information on licensing please see the README in the GitHub repository
// <https://github.com/gyrostable/concentrated-lps>.

pragma solidity ^0.8.24;

import { ISwapFeePercentageBounds } from "@balancer-labs/v3-interfaces/contracts/vault/ISwapFeePercentageBounds.sol";
import { PoolSwapParams, Rounding, SwapKind } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IGyro2CLPPool } from "@balancer-labs/v3-interfaces/contracts/pool-gyro/IGyro2CLPPool.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    IUnbalancedLiquidityInvariantRatioBounds
} from "@balancer-labs/v3-interfaces/contracts/vault/IUnbalancedLiquidityInvariantRatioBounds.sol";

import { BalancerPoolToken } from "@balancer-labs/v3-vault/contracts/BalancerPoolToken.sol";

import "./lib/Gyro2CLPMath.sol";

/**
 * @notice Standard 2CLP Gyro Pool, with fixed Alpha and Beta parameters.
 * @dev Gyroscope's 2-CLPs are AMMs that concentrate liquidity within a pricing range. A given 2-CLP is parameterized
 * by the pricing range [α,β] and the two assets in the pool. For more information, please refer to
 * https://docs.gyro.finance/gyroscope-protocol/concentrated-liquidity-pools/2-clps
 */
contract Gyro2CLPPool is IGyro2CLPPool, BalancerPoolToken {
    using FixedPoint for uint256;

    uint256 private immutable _sqrtAlpha;
    uint256 private immutable _sqrtBeta;

    bytes32 private constant _POOL_TYPE = "2CLP";

    constructor(GyroParams memory params, IVault vault) BalancerPoolToken(vault, params.name, params.symbol) {
        if (params.sqrtAlpha >= params.sqrtBeta) {
            revert SqrtParamsWrong();
        }

        _sqrtAlpha = params.sqrtAlpha;
        _sqrtBeta = params.sqrtBeta;
    }

    /// @inheritdoc IBasePool
    function computeInvariant(uint256[] memory balancesLiveScaled18, Rounding rounding) public view returns (uint256) {
        (uint256 sqrtAlpha, uint256 sqrtBeta) = _getSqrtAlphaAndBeta();

        return Gyro2CLPMath.calculateInvariant(balancesLiveScaled18, sqrtAlpha, sqrtBeta, rounding);
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
        // In computeBalance, we want to know the new balance of a token, given that the invariant
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

        (uint256 sqrtAlpha, uint256 sqrtBeta) = _getSqrtAlphaAndBeta();

        // `computeBalance` is used to calculate unbalanced adds and removes, when the BPT value is specified.
        // A bigger invariant in `computeAddLiquiditySingleTokenExactOut` means that more tokens are required to
        // fulfill the trade, and a bigger invariant in `computeRemoveLiquiditySingleTokenExactIn` means that the
        // amount out is lower. So, the invariant should always be rounded up.
        uint256 invariant = Gyro2CLPMath.calculateInvariant(
            balancesLiveScaled18,
            sqrtAlpha,
            sqrtBeta,
            Rounding.ROUND_UP
        );
        // New invariant
        invariant = invariant.mulUp(invariantRatio);
        uint256 squareNewInv = invariant * invariant;
        // L / sqrt(beta)
        uint256 a = invariant.divDown(sqrtBeta);
        // L * sqrt(alpha)
        uint256 b = invariant.mulDown(sqrtAlpha);

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
        (uint256 virtualParamIn, uint256 virtualParamOut) = _getVirtualBalances(
            balanceTokenInScaled18,
            balanceTokenOutScaled18,
            tokenInIsToken0,
            request.kind == SwapKind.EXACT_IN ? Rounding.ROUND_DOWN : Rounding.ROUND_UP
        );

        if (request.kind == SwapKind.EXACT_IN) {
            uint256 amountOutScaled18 = Gyro2CLPMath.calcOutGivenIn(
                balanceTokenInScaled18,
                balanceTokenOutScaled18,
                request.amountGivenScaled18,
                virtualParamIn,
                virtualParamOut
            );

            return amountOutScaled18;
        } else {
            uint256 amountInScaled18 = Gyro2CLPMath.calcInGivenOut(
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

    /// @notice Return the parameters that configure a 2CLP (sqrtAlpha and sqrtBeta).
    function _getSqrtAlphaAndBeta() internal view virtual returns (uint256 sqrtAlpha, uint256 sqrtBeta) {
        return (_sqrtAlpha, _sqrtBeta);
    }

    /**
     * @notice Return the virtual balances of each token of the 2CLP pool.
     * @dev The 2CLP invariant is defined as `L=(x+a)(y+b)`. "x" and "y" are the real balances, and "a" and "b" are
     * offsets to concentrate the liquidity of the pool. The sum of real balance and offset is known as
     * "virtual balance".
     */
    function _getVirtualBalances(
        uint256 balanceTokenInScaled18,
        uint256 balanceTokenOutScaled18,
        bool tokenInIsToken0,
        Rounding rounding
    ) internal view virtual returns (uint256 virtualBalanceIn, uint256 virtualBalanceOut) {
        uint256[] memory balances = new uint256[](2);
        balances[0] = tokenInIsToken0 ? balanceTokenInScaled18 : balanceTokenOutScaled18;
        balances[1] = tokenInIsToken0 ? balanceTokenOutScaled18 : balanceTokenInScaled18;

        (uint256 sqrtAlpha, uint256 sqrtBeta) = _getSqrtAlphaAndBeta();

        uint256 currentInvariant = Gyro2CLPMath.calculateInvariant(balances, sqrtAlpha, sqrtBeta, rounding);

        uint256[2] memory virtualBalances = _calculateVirtualBalances(currentInvariant, sqrtAlpha, sqrtBeta);

        virtualBalanceIn = tokenInIsToken0 ? virtualBalances[0] : virtualBalances[1];
        virtualBalanceOut = tokenInIsToken0 ? virtualBalances[1] : virtualBalances[0];
    }

    /// @notice Returns an array with virtual balances of both tokens of the pool, in registration order.
    function _calculateVirtualBalances(
        uint256 invariant,
        uint256 sqrtAlpha,
        uint256 sqrtBeta
    ) internal view virtual returns (uint256[2] memory virtualBalances) {
        virtualBalances[0] = Gyro2CLPMath.calculateVirtualParameter0(invariant, sqrtBeta);
        virtualBalances[1] = Gyro2CLPMath.calculateVirtualParameter1(invariant, sqrtAlpha);
        return virtualBalances;
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
