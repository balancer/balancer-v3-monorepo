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

    int256 constant ONE_INT = 1e18;

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

        uint256 D = pool.computeInvariant(lastBalancesLiveScaled18, Rounding.ROUND_DOWN);

        uint256[] memory balancesForPricesScaled18 = _computeBalancesForPrices(D, prices);

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

        (int256 a, int256 b) = _computeAAndBForPool(IStablePool(address(pool)));

        // First, we need to compute the constant k that will multiply the prices.
        int256 k = _computeK(a, b, prices);

        int256 sumPriceDivision = 0;
        for (uint256 i = 0; i < _totalTokens; i++) {
            sumPriceDivision += divDownInt(a, mulDownInt(k, prices[i]) - a);
        }

        balancesForPrices = new uint256[](_totalTokens);
        for (uint256 i = 0; i < _totalTokens; i++) {
            balancesForPrices[i] = ((-b * int256(invariant)) /
                mulDownInt(a - mulDownInt(k, prices[i]), ONE_INT - sumPriceDivision)).toUint256();
        }
    }

    function _computeK(int256 a, int256 b, int256[] memory prices) internal view returns (int256 k) {
        // k is computed by solving the equation:
        //
        // f(k) = T^(n+1)P + alpha = 0
        //
        // where `T=1+\sum{a/(a-k*pi)}`, `P = \prod{(a - k*pi)/a}` and `alpha=a*(-b/a)^(n+1)`.
        // Notice that a is a very small number, so P can be a very large number. To avoid math overflows, but keep
        // the precision, we divide f(k) and f'(k) by P, which allow us to don't compute P at all, only the derivative.

        // We start with a guess for k. Using a big k will make sure it converges to the positive root.
        k = _findInitialGuessForK(a, b, prices);
        for (uint256 i = 0; i < 255; i++) {
            // dTdk and dPdk are the derivatives of T and P with respect to k.
            (int256 T, int256 dTdk, int256 PTn, int256 dPdk, int256 alpha) = _computeKParams(k, a, b, prices);
            console2.log("---- k ----", k);
            console2.log("T", T);
            console2.log("dTdk", dTdk);
            console2.log("PTn", PTn);
            console2.log("dPdk", dPdk);
            console2.log("alpha", alpha);

            int256 fk = mulDownInt(PTn, T) - alpha;
            int256 dFkdk = mulDownInt(PTn, (int256(_totalTokens) + 1) * dTdk + mulDownInt(T, dPdk));

            int256 newK = k - divDownInt(fk, dFkdk);

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

    function _findInitialGuessForK(int256 a, int b, int256[] memory prices) internal view returns (int256 k) {
        int256 minPrice = prices[0];
        for (uint256 i = 1; i < _totalTokens; i++) {
            if (prices[i] < minPrice) {
                minPrice = prices[i];
            }
        }

        int256 term1 = ONE_INT + divDownInt(ONE_INT, (ONE_INT - b));
        int256 term2 = 2 * ONE_INT + divDownInt(b, a);

        if (term1 < term2) {
            return (term1 * a) / minPrice;
        } else {
            return (term2 * a) / minPrice;
        }
    }

    function _computeKParams(
        int256 k,
        int256 a,
        int256 b,
        int256[] memory prices
    ) internal view returns (int256 T, int256 dTdk, int256 PTn, int256 dPdk, int256 alpha) {
        uint256 i;
        int256 den;

        T = 0;
        dTdk = 0;
        dPdk = 0;
        for (i = 0; i < _totalTokens; i++) {
            den = mulDownInt(k, prices[i]) - a;
            T += divDownInt(a, den);
            dTdk -= divDownInt((prices[i] * a) / den, den);
            dPdk += divDownInt(prices[i], mulDownInt(k, prices[i]) - a);
        }
        T -= ONE_INT;

        alpha = -b;
        PTn = ONE_INT;
        for (i = 0; i < _totalTokens; i++) {
            int256 ri = divDownInt(prices[i], a);
            den = mulDownInt(k, ri) - ONE_INT;
            PTn = mulDownInt(mulDownInt(PTn, T), den);
            alpha = (alpha * -b) / a;
        }
    }

    function _computeAAndBForPool(IStablePool pool) internal view returns (int256 a, int256 b) {
        (uint256 amplificationFactor, , ) = pool.getAmplificationParameter();
        // a = A * n^2n, but A = ampParameter * n^(n-1). So, a = ampParameter * n^(2n)/n^(n-1) = ampParameter * n^(n+1).
        a = int256((amplificationFactor * (_totalTokens ** (_totalTokens + 1))).divDown(StableMath.AMP_PRECISION));
        b = int256(FixedPoint.ONE * (_totalTokens ** _totalTokens)) - a;
    }

    function divDownInt(int256 a, int256 b) internal pure returns (int256) {
        return (a * ONE_INT) / b;
    }

    function mulDownInt(int256 a, int256 b) internal pure returns (int256) {
        return (a * b) / ONE_INT;
    }

    function powDownInt(int256 a, uint256 n) internal pure returns (int256) {
        int256 result = ONE_INT;
        for (uint256 i = 0; i < n; i++) {
            result = mulDownInt(result, a);
        }
        return result;
    }
}
