// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

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
            uint256 nn = _totalTokens ** _totalTokens;
            a = A * (nn ** 2);
            b = nn * FixedPoint.ONE * precision - a;
            ampPrecision = precision;
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
        uint256 k = computeK(a, b, prices, ampPrecision);

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
            KParams memory kParams = computeKParams(k, a, b, prices, ampPrecision);

            // Calculate f(k).
            uint256 fk = kParams.Tn1.mulDown(kParams.P);
            if (_totalTokens % 2 == 1) {
                fk += kParams.alpha / FixedPoint.ONE;
            } else {
                fk -= kParams.alpha / FixedPoint.ONE;
            }

            // Calculate derivative of f(k) (`f'(k)`).
            uint256 flk = kParams.Tn.mulDown(
                ((_totalTokens + 1) * kParams.Tl.mulDown(kParams.P)) + kParams.T.mulDown(kParams.Pl)
            );

            uint256 newK = k - (fk.divDown(flk));

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
    }

    function computeKParams(
        uint256 k,
        uint256 a,
        uint256 b,
        int256[] memory prices,
        uint256 ampPrecision
    ) internal view returns (KParams memory kParams) {
        kParams.T = FixedPoint.ONE;
        kParams.Tl = 0;
        // P overflows for small amplification factors
        kParams.P = 1;
        kParams.Pl = 0;
        for (uint256 i = 0; i < _totalTokens; i++) {
            uint256 ri = (prices[i].toUint256() * ampPrecision).divDown(a);
            uint256 den = (k.mulDown(ri) - FixedPoint.ONE);
            kParams.T -= (FixedPoint.ONE).divDown(den);
            // den is a very large number, so we divide twice to avoid overflows.
            kParams.Tl += ri.divDown(den).divDown(den);
            kParams.P = kParams.P.mulDown(den);
            kParams.Pl += ri.divDown(den);
        }

        kParams.Pl = kParams.Pl.mulDown(kParams.P);

        uint256 c = b.divDown(a);
        kParams.Tn = FixedPoint.ONE;
        for (uint256 i = 0; i < _totalTokens; i++) {
            kParams.Tn = kParams.Tn.mulDown(kParams.T);
            c = (c * b) / a;
        }

        kParams.Tn1 = kParams.Tn.mulDown(kParams.T);
        kParams.alpha = a.mulDown(c) / ampPrecision;
    }
}
