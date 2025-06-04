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

    struct TVLLocals {
        uint256 D;
        uint256 n;
        uint256 A;
        uint256 nn;
        uint256 n2n;
        uint256 Dn;
        uint256 a;
        uint256 minusb;
    }

    /// @inheritdoc ILPOracleBase
    function calculateTVL(int256[] memory prices) public view override returns (uint256 tvl) {
        (, , , uint256[] memory lastBalancesLiveScaled18) = _vault.getPoolTokenInfo(address(pool));

        // TODO add description

        TVLLocals memory locals;

        locals.D = pool.computeInvariant(lastBalancesLiveScaled18, Rounding.ROUND_UP);
        locals.n = _totalTokens * FixedPoint.ONE;
        (locals.A, , ) = IStablePool(address(pool)).getAmplificationParameter();

        locals.nn = locals.n.powDown(locals.n);
        locals.n2n = locals.nn.mulDown(locals.nn);
        locals.Dn = locals.D.powDown(locals.n);

        locals.a = (locals.A * locals.n2n) / locals.Dn.divDown(locals.D);
        locals.minusb = (((locals.A * locals.n2n) / (locals.Dn.divDown(locals.D).divDown(locals.D))) -
            locals.D.mulDown(locals.nn));

        uint256 sumPriceDivision = 0;
        for (uint256 i = 0; i < _totalTokens; i++) {
            sumPriceDivision += FixedPoint.ONE.divDown(locals.a - prices[i].toUint256());
        }
        sumPriceDivision = locals.a.mulDown(sumPriceDivision);

        tvl = 0;
        for (uint256 i = 0; i < _totalTokens; i++) {
            uint256 balanceGradient = ((locals.minusb * locals.D) / (locals.a - prices[i].toUint256())).divDown(
                FixedPoint.ONE + sumPriceDivision
            );
            tvl += prices[i].toUint256() * balanceGradient;
        }

        return tvl;
    }
}
