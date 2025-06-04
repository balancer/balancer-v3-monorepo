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
            uint256 n = _totalTokens * FixedPoint.ONE;
            (uint256 A, , uint256 precision) = IStablePool(address(pool)).getAmplificationParameter();
            uint256 nn = n.powDown(n);
            a = A.mulDown(nn).mulDown(nn);
            b = nn.mulDown((FixedPoint.ONE * precision) - A.mulDown(nn));
            ampPrecision = precision;
        }

        uint256 sumPriceDivision = 0;
        for (uint256 i = 0; i < _totalTokens; i++) {
            // Round down, so balanceGradients is rounded down, which rounds the TVL down.
            sumPriceDivision += FixedPoint.ONE.divDown((prices[i].toUint256() * ampPrecision) - a);
        }
        sumPriceDivision = a.mulDown(sumPriceDivision);

        uint256[] memory balanceGradients = new uint256[](_totalTokens);
        for (uint256 i = 0; i < _totalTokens; i++) {
            balanceGradients[i] = (b.divDown((prices[i].toUint256() * ampPrecision) - a)).divDown(
                FixedPoint.ONE - sumPriceDivision
            );
        }

        // Round Up, so the TVL is rounded down.
        uint256 Dgradient = pool.computeInvariant(balanceGradients, Rounding.ROUND_UP);

        tvl = 0;
        for (uint256 i = 0; i < _totalTokens; i++) {
            tvl += prices[i].toUint256().mulDown((balanceGradients[i] * D) / Dgradient);
        }

        return tvl;
    }
}
