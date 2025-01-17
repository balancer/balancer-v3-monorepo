// SPDX-License-Identifier: LicenseRef-Gyro-1.0
// for information on licensing please see the README in the GitHub repository
// <https://github.com/gyrostable/concentrated-lps>.

pragma solidity ^0.8.24;

import { ISwapFeePercentageBounds } from "@balancer-labs/v3-interfaces/contracts/vault/ISwapFeePercentageBounds.sol";
import { PoolSwapParams, Rounding, SwapKind } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import {
    IGyro2CLPPool,
    Gyro2CLPPoolDynamicData,
    Gyro2CLPPoolImmutableData
} from "@balancer-labs/v3-interfaces/contracts/pool-gyro/IGyro2CLPPool.sol";
import {
    IUnbalancedLiquidityInvariantRatioBounds
} from "@balancer-labs/v3-interfaces/contracts/vault/IUnbalancedLiquidityInvariantRatioBounds.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { Version } from "@balancer-labs/v3-solidity-utils/contracts/helpers/Version.sol";
import { PoolInfo } from "@balancer-labs/v3-pool-utils/contracts/PoolInfo.sol";
import { BalancerPoolToken } from "@balancer-labs/v3-vault/contracts/BalancerPoolToken.sol";

import "./lib/Gyro2CLPMath.sol";

/**
 * @notice Standard 2-CLP Gyro Pool, with fixed Alpha and Beta parameters.
 * @dev Gyroscope's 2-CLPs are AMMs that concentrate liquidity within a pricing range. A given 2-CLP is parameterized
 * by the pricing range [α,β] and the two assets in the pool. For more information, please refer to
 * https://docs.gyro.finance/gyroscope-protocol/concentrated-liquidity-pools/2-clps
 */
contract Gyro2CLPPool is IGyro2CLPPool, BalancerPoolToken, PoolInfo, Version {
    using FixedPoint for uint256;

    uint256 private immutable _sqrtAlpha;
    uint256 private immutable _sqrtBeta;

    constructor(
        GyroParams memory params,
        IVault vault
    ) BalancerPoolToken(vault, params.name, params.symbol) PoolInfo(vault) Version(params.version) {
        if (params.sqrtAlpha >= params.sqrtBeta) {
            revert SqrtParamsWrong();
        }

        _sqrtAlpha = params.sqrtAlpha;
        _sqrtBeta = params.sqrtBeta;
    }

    /// @inheritdoc IBasePool
    function computeInvariant(
        uint256[] memory balancesLiveScaled18,
        Rounding rounding
    ) external view returns (uint256) {
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

        // L / sqrt(beta), rounded down to maximize newBalance.
        uint256 a = invariant.divDown(sqrtBeta);
        // L * sqrt(alpha), rounded down to maximize newBalance (b is in the denominator).
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
    function onSwap(PoolSwapParams calldata request) external view onlyVault returns (uint256) {
        bool tokenInIsToken0 = request.indexIn == 0;
        uint256 balanceTokenInScaled18 = request.balancesScaled18[request.indexIn];
        uint256 balanceTokenOutScaled18 = request.balancesScaled18[request.indexOut];

        // All the calculations in one function to avoid Error Stack Too Deep
        (uint256 virtualParamIn, uint256 virtualParamOut) = _getVirtualOffsets(
            balanceTokenInScaled18,
            balanceTokenOutScaled18,
            tokenInIsToken0
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

    /// @notice Return the parameters that configure a 2-CLP (sqrtAlpha and sqrtBeta).
    function _getSqrtAlphaAndBeta() internal view virtual returns (uint256 sqrtAlpha, uint256 sqrtBeta) {
        return (_sqrtAlpha, _sqrtBeta);
    }

    /**
     * @notice Return the virtual offsets of each token of the 2-CLP pool.
     * @dev The 2-CLP invariant is defined as `L=(x+a)(y+b)`. "x" and "y" are the real balances, and "a" and "b" are
     * offsets to concentrate the liquidity of the pool. The sum of real balance and offset is known as
     * "virtual balance". Here we return the offsets a and b.
     */
    function _getVirtualOffsets(
        uint256 balanceTokenInScaled18,
        uint256 balanceTokenOutScaled18,
        bool tokenInIsToken0
    ) internal view virtual returns (uint256 virtualBalanceIn, uint256 virtualBalanceOut) {
        uint256[] memory balances = new uint256[](2);
        balances[0] = tokenInIsToken0 ? balanceTokenInScaled18 : balanceTokenOutScaled18;
        balances[1] = tokenInIsToken0 ? balanceTokenOutScaled18 : balanceTokenInScaled18;

        (uint256 sqrtAlpha, uint256 sqrtBeta) = _getSqrtAlphaAndBeta();

        uint256 currentInvariant = Gyro2CLPMath.calculateInvariant(balances, sqrtAlpha, sqrtBeta, Rounding.ROUND_DOWN);

        // virtualBalanceIn is always rounded up, because:
        // * If swap is EXACT_IN: a bigger virtualBalanceIn leads to a lower amount out;
        // * If swap is EXACT_OUT: a bigger virtualBalanceIn leads to a bigger amount in;
        // virtualBalanceOut is always rounded down, because:
        // * If swap is EXACT_IN: a lower virtualBalanceOut leads to a lower amount out;
        // * If swap is EXACT_OUT: a lower virtualBalanceOut leads to a bigger amount in;
        if (tokenInIsToken0) {
            virtualBalanceIn = Gyro2CLPMath.calculateVirtualParameter0(currentInvariant, sqrtBeta, Rounding.ROUND_UP);
            virtualBalanceOut = Gyro2CLPMath.calculateVirtualParameter1(
                currentInvariant,
                sqrtAlpha,
                Rounding.ROUND_DOWN
            );
        } else {
            virtualBalanceIn = Gyro2CLPMath.calculateVirtualParameter1(currentInvariant, sqrtAlpha, Rounding.ROUND_UP);
            virtualBalanceOut = Gyro2CLPMath.calculateVirtualParameter0(
                currentInvariant,
                sqrtBeta,
                Rounding.ROUND_DOWN
            );
        }
    }

    /// @inheritdoc ISwapFeePercentageBounds
    function getMinimumSwapFeePercentage() external pure returns (uint256) {
        // Liquidity Approximation tests show that add/remove liquidity combinations are more profitable than a swap
        // if the swap fee percentage is 0%, which is not desirable. So, a minimum percentage must be enforced.
        return 1e12; // 0.0001%
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

    /// @inheritdoc IGyro2CLPPool
    function getGyro2CLPPoolDynamicData() external view returns (Gyro2CLPPoolDynamicData memory data) {
        data.balancesLiveScaled18 = _vault.getCurrentLiveBalances(address(this));
        (, data.tokenRates) = _vault.getPoolTokenRates(address(this));
        data.staticSwapFeePercentage = _vault.getStaticSwapFeePercentage((address(this)));
        data.totalSupply = totalSupply();
        data.bptRate = getRate();

        PoolConfig memory poolConfig = _vault.getPoolConfig(address(this));
        data.isPoolInitialized = poolConfig.isPoolInitialized;
        data.isPoolPaused = poolConfig.isPoolPaused;
        data.isPoolInRecoveryMode = poolConfig.isPoolInRecoveryMode;
    }

    /// @inheritdoc IGyro2CLPPool
    function getGyro2CLPPoolImmutableData() external view returns (Gyro2CLPPoolImmutableData memory data) {
        data.tokens = _vault.getPoolTokens(address(this));
        (data.decimalScalingFactors, ) = _vault.getPoolTokenRates(address(this));
        data.sqrtAlpha = _sqrtAlpha;
        data.sqrtBeta = _sqrtBeta;
    }
}
