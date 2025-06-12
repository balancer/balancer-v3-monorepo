// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { ILPOracleBase } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/ILPOracleBase.sol";
import { IStablePool } from "@balancer-labs/v3-interfaces/contracts/pool-stable/IStablePool.sol";
import { Rounding } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { LPOracleBase } from "./LPOracleBase.sol";

contract StableLPOracle is LPOracleBase {
    using FixedPoint for uint256;
    using SafeCast for *;

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

        // TODO add description

        uint256 D = pool.computeInvariant(lastBalancesLiveScaled18, Rounding.ROUND_DOWN);

        uint256 a;
        uint256 b;
        uint256 ampPrecision;
        {
            (uint256 A, , uint256 precision) = IStablePool(address(pool)).getAmplificationParameter();
            console2.log("A", A);
            uint256 nn = _totalTokens ** _totalTokens;
            a = A * (nn ** 2);
            b = nn * FixedPoint.ONE * precision - a;
            ampPrecision = precision;
        }

        console2.log("D", D);
        console2.log("n", _totalTokens);
        for (uint256 i = 0; i < _totalTokens; i++) {
            console2.log("prices[i]", prices[i]);
        }

        uint256[] memory balancesForPrices = computeBalancesForPrices(D, a, b, prices, ampPrecision);

        tvl = 0;
        for (uint256 i = 0; i < _totalTokens; i++) {
            tvl += prices[i].toUint256().mulDown(balancesForPrices[i]);
        }

        return tvl;
    }

    function computeBalancesForPrices(
        uint256 invariant,
        uint256 a,
        uint256 b,
        int256[] memory prices,
        uint256 ampPrecision
    ) internal view returns (uint256[] memory balancesForPrices) {
        console2.log("Start K");
        uint256 k = computeK(a, b, prices, ampPrecision);
        console2.log("k", k);

        uint256 sumPriceDivision = 0;
        for (uint256 i = 0; i < _totalTokens; i++) {
            sumPriceDivision += a.divUp(k.mulUp(prices[i].toUint256()) * ampPrecision - a);
        }

        balancesForPrices = new uint256[](_totalTokens);
        for (uint256 i = 0; i < _totalTokens; i++) {
            balancesForPrices[i] = ((b * invariant) / (k.mulUp(prices[i].toUint256()) * ampPrecision - a)).divDown(
                FixedPoint.ONE - sumPriceDivision
            );
        }
    }

    function computeK(
        uint256 a,
        uint256 b,
        int256[] memory prices,
        uint256 ampPrecision
    ) internal view returns (uint256 k) {
        k = 10000e18;
        for (uint256 i = 0; i < 255; i++) {
            console2.log("current k", k);
            KParams memory kParams = computeKParams(k, a, b, prices, ampPrecision);

            // Calculate derivative of f(k) (`f'(k)`).
            uint256 flk = mulDownReductionFactor(
                kParams.Tn,
                (_totalTokens + 1) * kParams.Tl.mulDown(kParams.P) + kParams.T.mulDown(kParams.Pl),
                kParams.reductionFactor
            );

            // Calculate f(k).
            uint256 fk = mulDownReductionFactor(kParams.Tn1, kParams.P, kParams.reductionFactor);
            uint256 newK;

            if (kParams.alpha > fk) {
                fk = kParams.alpha - fk;
                newK = k + (fk.divDown(flk));
            } else {
                fk = fk - kParams.alpha;
                newK = k - (fk.divDown(flk));
            }

            if (newK > k && (newK - k) <= 1e10) {
                return newK;
            } else if (newK < k && (k - newK) <= 1e10) {
                return newK;
            }
            k = newK;
        }

        // TODO Raise Exception
    }

    struct KParams {
        uint256 T;
        uint256 Tl;
        uint256 P;
        uint256 Pl;
        uint256 Tn;
        uint256 Tn1;
        uint256 alpha;
        uint256 reductionFactor;
    }

    function computeKParams(
        uint256 k,
        uint256 a,
        uint256 b,
        int256[] memory prices,
        uint256 ampPrecision
    ) internal view returns (KParams memory kParams) {
        // It'll reduce numbers by reductionFactor^n, so operations won't overflow.
        kParams.reductionFactor = 1;
        kParams.T = FixedPoint.ONE;
        kParams.Tl = 0;
        // P overflows with small amp factor, or small prices, or number of tokens. So, we don't use FP.ONE.
        // Instead, we scale the calculation of f(k) down by FP.ONE, by dividing alpha by FP.ONE.
        kParams.P = FixedPoint.ONE;
        kParams.Pl = 0;
        for (uint256 i = 0; i < _totalTokens; i++) {
            uint256 ri = (prices[i].toUint256() * ampPrecision).divDown(a);
            uint256 den = (k.mulDown(ri) - FixedPoint.ONE);
            kParams.T -= (FixedPoint.ONE).divDown(den);
            // den is a very large number, so we divide twice to avoid overflows.
            kParams.Tl += ri.divDown(den).divDown(den);
            kParams.P = ((kParams.P / FixedPoint.ONE) * den) / kParams.reductionFactor;
            kParams.Pl += ri.divDown(den);
        }
        kParams.P = kParams.P / FixedPoint.ONE;
        kParams.Pl = (kParams.P / FixedPoint.ONE) * kParams.Pl;

        // Since the precision of P was removed, remove the precision of c dividing using a raw division.
        uint256 c = b / a;
        kParams.Tn = FixedPoint.ONE;
        for (uint256 i = 0; i < _totalTokens; i++) {
            kParams.Tn = kParams.Tn.mulDown(kParams.T) / kParams.reductionFactor;
            c = ((c * b) / a) / kParams.reductionFactor;
        }

        kParams.Tn1 = kParams.Tn.mulDown(kParams.T);

        kParams.alpha = a.mulDown(c) / (ampPrecision);
    }

    function mulDownReductionFactor(uint256 a, uint256 b, uint256 reductionFactor) internal view returns (uint256) {
        return (a * b) / (FixedPoint.ONE / (reductionFactor ** _totalTokens));
    }
}
