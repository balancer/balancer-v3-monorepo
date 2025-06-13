// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
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

contract StableLPOracle is LPOracleBase {
    using FixedPoint for uint256;
    using SafeCast for *;

    // Thrown when the k parameter did not converge to the positive root.
    error KDidntConverge();

    constructor(
        IVault vault_,
        IStablePool pool_,
        AggregatorV3Interface[] memory feeds,
        uint256 version_
    ) LPOracleBase(vault_, IBasePool(address(pool_)), feeds, version_) {
        // TODO: Implement
    }

    /// @inheritdoc ILPOracleBase
    function calculateTVL(int256[] memory prices) public view override returns (uint256 tvl) {
        (, , , uint256[] memory lastBalancesLiveScaled18) = _vault.getPoolTokenInfo(address(pool));

        // The TVL of the stable pool is computed by calculating the balances for the stable pool that would represent
        // the given price vector. To compute these balances, we need only the amplification parameter of the pool,
        // the invariant and the price vector.

        // The invariant of the stable pool is not accurate, so it can increase in solidity when the pool is at the
        // edge, even though using precision math the invariant is the same. So, we first compute the balances when
        // the pool is perfectly balanced, then compute the invariant again and finally compute the balances that
        // represents the price array.
        uint256 D = pool.computeInvariant(lastBalancesLiveScaled18, Rounding.ROUND_DOWN);

        int256[] memory pricesEqual = new int256[](_totalTokens);
        for (uint256 i = 0; i < _totalTokens; i++) {
            pricesEqual[i] = int256(FixedPoint.ONE);
        }

        uint256[] memory balancesForEquilibriumScaled18 = _computeBalancesForPrices(D, pricesEqual);

        uint256 smallestD = pool.computeInvariant(balancesForEquilibriumScaled18, Rounding.ROUND_DOWN);
        if (D < smallestD) {
            smallestD = D;
        }

        // Normalizes the price array according to the first token price.
        int256[] memory normalizedPrices = new int256[](_totalTokens);
        for (uint256 i = 0; i < _totalTokens; i++) {
            normalizedPrices[i] = int256(prices[i].toUint256().divDown(prices[0].toUint256()));
        }

        uint256[] memory balancesForPricesScaled18 = _computeBalancesForPrices(smallestD, normalizedPrices);

        uint256 newD = pool.computeInvariant(balancesForPricesScaled18, Rounding.ROUND_DOWN);

        // The new invariant will be bigger than the previous one, since the computed balances are unbalanced according
        // to the price vector. So, we normalize the balances according to the invariants, to make sure we're not
        // inflating the value of the pool.
        for (uint256 i = 0; i < _totalTokens; i++) {
            balancesForPricesScaled18[i] = (balancesForPricesScaled18[i] * smallestD) / newD;
        }

        tvl = 0;
        for (uint256 i = 0; i < _totalTokens; i++) {
            tvl += prices[i].toUint256().mulDown(balancesForPricesScaled18[i]);
        }

        return tvl;
    }

    function _computeBalancesForPrices(
        uint256 invariant,
        int256[] memory prices
    ) internal view returns (uint256[] memory balancesForPrices) {
        // To compute the balances for a given price vector, we need to compute the gradient of the stable invariant.
        // The stable invariant is:
        //
        // a \sum{xi} \prod{xi} +bD \prod{xi} - D^(n+1) = 0
        //
        // where `D` is the invariant, `n` is the number of tokens, `xi` is the balance of each token,
        // `a = A*(n^2n)` and `b = n^n - a`.
        //
        // The gradient in terms of xj (the balance of the j-th token) is:
        //
        // a \prod{xi} + a \sum{xi} \prod_i!=j{xi} + bD \prod_i!=j{xi}
        //
        // We can make this gradient equal to k*pj, where pj is the price of the j-th token and k is a constant.
        // Then, solving this system of equations for every pj, we will have an array of balances that respect the
        // price vector.

        (uint256 a, uint256 b) = _computeAAndBForPool(IStablePool(address(pool)));

        // First, we need to compute the constant k that will multiply the prices.
        uint256 k = _computeK(a, b, prices);

        uint256 sumPriceDivision = 0;
        for (uint256 i = 0; i < _totalTokens; i++) {
            sumPriceDivision += (FixedPoint.ONE).divDown(k.mulDown(prices[i].toUint256()) - a);
        }
        sumPriceDivision = sumPriceDivision.mulDown(a);

        balancesForPrices = new uint256[](_totalTokens);
        for (uint256 i = 0; i < _totalTokens; i++) {
            balancesForPrices[i] =
                (b * invariant).divDown((k).mulUp(prices[i].toUint256()) - a) /
                (FixedPoint.ONE - sumPriceDivision);
        }
    }

    function _computeK(uint256 a, uint256 b, int256[] memory prices) internal view returns (uint256 k) {
        // k is computed by solving the equation:
        //
        // f(k) = T^(n+1)P + alpha = 0
        //
        // where `T=1+\sum{a/(a-k*pi)}`, `P = \prod{(a - k*pi)/a}` and `alpha=a*(-b/a)^(n+1)`.
        // Notice that a is a very small number, so P can be a very large number. To avoid math overflows, but keep
        // the precision, we divide f(k) and f'(k) by P, which allow us to don't compute P at all, only the derivative.

        // We start with a guess for k. Using a big k will make sure it converges to the positive root.
        k = 10000e18;
        for (uint256 i = 0; i < 255; i++) {
            // dTdk and dPdk are the derivatives of T and P with respect to k.
            (uint256 T, uint256 dTdk, uint256 dPdk, uint256 Tn, uint256 alpha) = _computeKParams(k, a, b, prices);

            // Alpha is actually alpha / P, to avoid overflows. So, P is not used.
            uint256 flk = (_totalTokens + 1) * Tn.divDown(T).mulDown(dTdk) + T.mulDown(dPdk);

            uint256 newK;

            if (alpha > Tn) {
                newK = k + ((alpha - Tn).divDown(flk));
            } else {
                newK = k - ((Tn - alpha).divDown(flk));
            }

            if (newK > k) {
                if ((newK - k) <= 1e7) {
                    return newK;
                }
            } else if ((k - newK) <= 1e7) {
                return newK;
            }

            k = newK;
        }

        revert KDidntConverge();
    }

    function _computeKParams(
        uint256 k,
        uint256 a,
        uint256 b,
        int256[] memory prices
    ) internal view returns (uint256 T, uint256 dTdk, uint256 dPdk, uint256 Tn, uint256 alpha) {
        uint256 i;
        uint256 den;

        uint256[] memory p = new uint256[](_totalTokens);
        for (i = 0; i < _totalTokens; i++) {
            p[i] = prices[i].toUint256();
        }

        T = FixedPoint.ONE;
        dTdk = 0;
        dPdk = 0;
        for (i = 0; i < _totalTokens; i++) {
            den = (k.mulDown(p[i]) - a);
            T -= a.divDown(den);
            dTdk += ((p[i] * a) / (den.mulDown(den)));
            dPdk += (p[i]).divDown(den);
        }

        alpha = b;
        Tn = FixedPoint.ONE;

        for (i = 0; i < _totalTokens; i++) {
            den = ((k).mulDown(p[i]) - a);
            Tn = Tn.mulDown(T);
            alpha = (alpha * b) / den;
        }
        alpha = alpha;
    }

    function _computeAAndBForPool(IStablePool pool) internal view returns (uint256 a, uint256 b) {
        (uint256 amplificationFactor, , ) = pool.getAmplificationParameter();
        uint256 nn = _totalTokens ** _totalTokens;
        a = (amplificationFactor * (nn ** 2)) / StableMath.AMP_PRECISION;
        b = nn * FixedPoint.ONE - a;
    }
}
