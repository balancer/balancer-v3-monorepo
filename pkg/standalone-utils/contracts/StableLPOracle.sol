// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import { SignedMath } from "@openzeppelin/contracts/utils/math/SignedMath.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { ILPOracleBase } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/ILPOracleBase.sol";
import { IStablePool } from "@balancer-labs/v3-interfaces/contracts/pool-stable/IStablePool.sol";
import { Rounding } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { StableMath } from "@balancer-labs/v3-solidity-utils/contracts/math/StableMath.sol";

import { LPOracleBase } from "./LPOracleBase.sol";

/**
 * @notice Oracle for stable pools.
 */
contract StableLPOracle is LPOracleBase {
    using FixedPoint for uint256;
    using SafeCast for *;

    // The `k` parameter did not converge to the positive root.
    error KDidNotConverge();

    int256 private constant _POSITIVE_ONE_INT = 1e18;
    uint256 private constant _K_MAX_ERROR = 1e4;

    constructor(
        IVault vault_,
        IStablePool pool_,
        AggregatorV3Interface[] memory feeds,
        uint256 version_
    ) LPOracleBase(vault_, IBasePool(address(pool_)), feeds, version_) {
        // solhint-disable-previous-line no-empty-blocks
    }

    /// @inheritdoc ILPOracleBase
    function calculateTVL(int256[] memory prices) public view override returns (uint256 tvl) {
        (, , , uint256[] memory lastBalancesLiveScaled18) = _vault.getPoolTokenInfo(address(pool));
        InputHelpers.ensureInputLengthMatch(prices.length, lastBalancesLiveScaled18.length);

        // The TVL of the stable pool is computed by calculating the balances for the stable pool that would represent
        // the given price vector. To compute these balances, we need only the amplification parameter of the pool,
        // the invariant and the price vector.

        uint256 invariant = pool.computeInvariant(lastBalancesLiveScaled18, Rounding.ROUND_DOWN);

        uint256[] memory marketPriceBalancesScaled18 = _computeMarketPriceBalances(invariant, prices);

        for (uint256 i = 0; i < _totalTokens; i++) {
            tvl += prices[i].toUint256().mulDown(marketPriceBalancesScaled18[i]);
        }

        return tvl;
    }

    /**
     * @notice Computes a set of balances for a given price vector and a given invariant.
     * @dev The set of balances should meet two conditions:
     * 1. The invariant of the computed balances should be equal to the given invariant.
     * 2. The spot prices of the computed balances should be equal to the given price vector. In other words:
     *    `spotPrice(i, j) == prices[i] / prices[j]`
     */
    function _computeMarketPriceBalances(
        uint256 invariant,
        int256[] memory prices
    ) internal view returns (uint256[] memory balancesForPrices) {
        // To compute the balances for a given price vector, we need to compute the gradient of the stable invariant.
        // The stable invariant is:
        //
        // D = invariant
        // S = sum of balances
        // P = product of balances
        // n = number of tokens                 a * S * P + b * D * P - D^(n+1) = 0
        // A = amplification coefficient
        // a = A * (n^2n)
        // b = a - n^n
        //
        // The gradient in terms of xj (the balance of the j-th token) is:
        //
        // a * P + a * S * P_notJ + b * D * P_notJ = 0
        //
        // where P_notJ is the product of all balances except the j-th token.
        //
        // We can make this gradient equal to k * pj, where pj is the price of the j-th token and k is a constant.
        // Then, solving this system of equations for every pj, we will have an array of balances that reflect the
        // price vector.

        (int256 a, int256 b) = _computeAAndBForPool(IStablePool(address(pool)));

        // First, we need to compute the constant k that will be used as a multiplier on all the prices.
        // This factor adjusts the input prices to find the correct balance amounts that respect both the pool
        // invariant and the desired token price ratios.
        int256 k = _computeK(a, b, prices);

        int256 sumPriceDivision = 0;
        for (uint256 i = 0; i < _totalTokens; i++) {
            sumPriceDivision += _divDownInt(a, _mulDownInt(k, prices[i]) - a);
        }

        balancesForPrices = new uint256[](_totalTokens);
        for (uint256 i = 0; i < _totalTokens; i++) {
            balancesForPrices[i] = ((b * int256(invariant)) /
                _mulDownInt(a - _mulDownInt(k, prices[i]), _POSITIVE_ONE_INT - sumPriceDivision)).toUint256();
        }
    }

    function _computeK(int256 a, int256 b, int256[] memory prices) internal view returns (int256 k) {
        // k is computed by solving the equation:
        //
        // T = 1 + Σ (a/(a-k*pi))
        // P = π ((a - k*pi)/a)         G(k) = T^(n+1)P - alpha = 0
        // alpha = a * (b/a)^(n+1)
        //
        // Notice that P*T^n can be a very big number. To avoid math overflows, but keep the precision, we divide
        // G(k) and G'(k) by P*T^n.

        k = _findInitialGuessForK(a, b, prices);
        for (uint256 i = 0; i < 255; i++) {
            // dTdk and dPdk are the derivatives of T and P with respect to k.
            // solhint-disable-next-line var-name-mixedcase
            (int256 T, int256 dTdk, int256 dPdkDivP, int256 alphaDivPTn) = _computeKParams(k, a, b, prices);

            int256 gk = T - alphaDivPTn;
            int256 dGkdk = (int256(_totalTokens) + 1) * dTdk + _mulDownInt(T, dPdkDivP);

            int256 newK = k - _divDownInt(gk, dGkdk);

            uint256 error = SignedMath.abs(_divDownInt(newK - k, k));
            if (error <= _K_MAX_ERROR) {
                return newK;
            }

            k = newK;
        }

        revert KDidNotConverge();
    }

    function _findInitialGuessForK(int256 a, int256 b, int256[] memory prices) internal view returns (int256 k) {
        // The initial guess for K is important, since f(k) has many roots that return negative balances. We need to
        // choose a guess where the function is convex.
        // The best initial guess for K is `k = a * min([(1 + 1/(1 + b)), (2 - b/a)]) / min(price)`.

        int256 minPrice = prices[0];
        for (uint256 i = 1; i < _totalTokens; i++) {
            if (prices[i] < minPrice) {
                minPrice = prices[i];
            }
        }

        int256 term1 = _POSITIVE_ONE_INT + _divDownInt(_POSITIVE_ONE_INT, (_POSITIVE_ONE_INT + b));
        int256 term2 = 2 * _POSITIVE_ONE_INT - _divDownInt(b, a);

        return (a * SignedMath.min(term1, term2)) / minPrice;
    }

    function _computeKParams(
        int256 k,
        int256 a,
        int256 b,
        int256[] memory prices
    ) internal view returns (int256 T, int256 dTdk, int256 dPdkDivP, int256 alphaDivPTn) {
        // solhint-disable-previous-line var-name-mixedcase

        uint256 i;
        int256 den;

        // To avoid overflows, we divided f(k) and f'(k) by PT^n. That's why, instead of computing P, P' and alpha,
        // we change the variables to compute `dPdkDivP = P'/P` and `alphaDivPTn = alpha/(PT^n)`.

        T = 0;
        // dTdk = T', where T' is the derivative of T with respect to k.
        dTdk = 0;
        // dPdkDivP = P'/P, where P' is the derivative of P with respect to k.
        dPdkDivP = 0;
        // alphaDivPTn = alpha/(PT^n), where alpha is the constant term of the stable invariant.
        alphaDivPTn = b;
        for (i = 0; i < _totalTokens; i++) {
            den = _mulDownInt(k, prices[i]) - a;
            T += _divDownInt(a, den);
            dTdk -= _divDownInt((prices[i] * a) / den, den);
            dPdkDivP += _divDownInt(prices[i], _mulDownInt(k, prices[i]) - a);
            alphaDivPTn = (alphaDivPTn * b) / a;
        }
        T -= _POSITIVE_ONE_INT;

        // We need to calculate T and alpha first to be able to divide alpha by PT^n.
        for (i = 0; i < _totalTokens; i++) {
            int256 ri = _divDownInt(prices[i], a);
            // P = π (k*ri - 1) . So, to divide alpha by PT^n, we can iteratively divide alpha by T and (k*ri - 1).
            den = _mulDownInt(k, ri) - _POSITIVE_ONE_INT;
            alphaDivPTn = _divDownInt(alphaDivPTn, _mulDownInt(den, T));
        }
    }

    /**
     * @notice Computes `a` and `b` parameters used in the gradient function that determines the market-price balances.
     * @dev This function returns scaled-18 values, and that's why we use FP math instead of raw math. During some
     * computations (e.g. `b/a`) we need FP precision, so return these variables as scaled-18 is convenient.
     */
    function _computeAAndBForPool(IStablePool pool) internal view returns (int256 a, int256 b) {
        (uint256 amplificationParameter, , ) = pool.getAmplificationParameter();
        // In the StableMath library, `amplificationParameter` = A * n^(n-1)
        // (For more information, check the `computeInvariant` NatSpec of the StableMath library.)
        //
        // Given that:
        // `A` = ampParameter / n^(n-1); and
        // `a` = A * n^2n
        //
        // We have: `a` = ampParameter * n^(2n) / n^(n-1) = ampParameter * n^(n+1)
        //
        // Since `2 <= totalTokens <= 5`; and
        // 1 <= amplificationParameter / AMP_PRECISION <= 50,000
        //
        // The max value of `a` is given by: 5^6 * 50000 = 781,250,000
        // This value, multiplied by 1e18, is far less than the int256 max positive value of 5.78e76.
        // Since there's no risk of Underflow/Overflow, we don't need to use SafeCast.
        a = int256((amplificationParameter * (_totalTokens ** (_totalTokens + 1))).divDown(StableMath.AMP_PRECISION));
        b = a - int256(FixedPoint.ONE * (_totalTokens ** _totalTokens));
    }

    function _divDownInt(int256 a, int256 b) internal pure returns (int256) {
        return (a * _POSITIVE_ONE_INT) / b;
    }

    function _mulDownInt(int256 a, int256 b) internal pure returns (int256) {
        return (a * b) / _POSITIVE_ONE_INT;
    }
}
