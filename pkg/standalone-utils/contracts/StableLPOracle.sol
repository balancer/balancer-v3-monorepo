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
import { StableMath } from "@balancer-labs/v3-solidity-utils/contracts/math/StableMath.sol";

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

        uint256[] memory balancesForPrices = _computeBalancesForPrices(D, prices);

        tvl = 0;
        for (uint256 i = 0; i < _totalTokens; i++) {
            tvl += prices[i].toUint256().mulDown(balancesForPrices[i]);
        }

        return tvl;
    }

    function _computeBalancesForPrices(
        uint256 invariant,
        int256[] memory prices
    ) internal view returns (uint256[] memory balancesForPrices) {
        (uint256 a, uint256 b) = _computeAAndBForPool(IStablePool(address(pool)));

        uint256 k = _computeK(a, b, prices);

        uint256 sumPriceDivision = 0;
        for (uint256 i = 0; i < _totalTokens; i++) {
            sumPriceDivision += a.divUp(k.mulUp(prices[i].toUint256()) * StableMath.AMP_PRECISION - a);
        }

        balancesForPrices = new uint256[](_totalTokens);
        for (uint256 i = 0; i < _totalTokens; i++) {
            balancesForPrices[i] = ((b * invariant) / (k.mulUp(prices[i].toUint256()) * StableMath.AMP_PRECISION - a))
                .divDown(FixedPoint.ONE - sumPriceDivision);
        }
    }

    function _computeK(uint256 a, uint256 b, int256[] memory prices) internal view returns (uint256 k) {
        k = 10000e18;
        for (uint256 i = 0; i < 255; i++) {
            (uint256 T, uint256 dTdK, uint256 dPdk, uint256 Tn, uint256 alpha) = _computeKParams(k, a, b, prices);

            // Alpha is actually alpha / P, to avoid overflows. So, P is not used.
            uint256 flk = (_totalTokens + 1) * Tn.divDown(T).mulDown(dTdK) + T.mulDown(dPdk);

            uint256 newK;

            if (alpha > Tn) {
                newK = k + ((alpha - Tn).divDown(flk));
            } else {
                newK = k - ((Tn - alpha).divDown(flk));
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

    function _computeKParams(
        uint256 k,
        uint256 a,
        uint256 b,
        int256[] memory prices
    ) internal view returns (uint256 T, uint256 dTdK, uint256 dPdk, uint256 Tn, uint256 alpha) {
        uint256 i;
        uint256 ri;
        uint256 den;

        // TODO exdPdkain that P is a very large number, so we divided f(k) and f'(k) by P to avoid overflows.
        T = FixedPoint.ONE;
        dTdK = 0;
        dPdk = 0;
        for (i = 0; i < _totalTokens; i++) {
            ri = (prices[i].toUint256() * StableMath.AMP_PRECISION).divDown(a);
            den = (k.mulDown(ri) - FixedPoint.ONE);
            T -= (FixedPoint.ONE).divDown(den);
            // den is a very large number, so we divide twice to avoid overflows.
            dTdK += ri.divDown(den).divDown(den);
            dPdk += ri.divDown(den);
        }

        alpha = b;
        Tn = FixedPoint.ONE;
        for (i = 0; i < _totalTokens; i++) {
            ri = (prices[i].toUint256() * StableMath.AMP_PRECISION).divDown(a);
            den = (k.mulDown(ri) - FixedPoint.ONE);
            Tn = Tn.mulDown(T);
            alpha = ((alpha * b) / a).divDown(den);
        }

        alpha = alpha / StableMath.AMP_PRECISION;
    }

    function _computeAAndBForPool(IStablePool pool) internal view returns (uint256 a, uint256 b) {
        (uint256 amplificationFactor, , ) = pool.getAmplificationParameter();
        uint256 nn = _totalTokens ** _totalTokens;
        a = amplificationFactor * (nn ** 2);
        b = nn * FixedPoint.ONE * StableMath.AMP_PRECISION - a;
    }
}
