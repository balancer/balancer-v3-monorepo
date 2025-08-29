// SPDX-License-Identifier: LicenseRef-Gyro-1.0

pragma solidity ^0.8.24;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { IGyroECLPPool } from "@balancer-labs/v3-interfaces/contracts/pool-gyro/IGyroECLPPool.sol";
import { ILPOracleBase } from "@balancer-labs/v3-interfaces/contracts/oracles/ILPOracleBase.sol";
import { Rounding } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { SignedFixedPoint } from "@balancer-labs/v3-pool-gyro/contracts/lib/SignedFixedPoint.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { GyroECLPMath } from "@balancer-labs/v3-pool-gyro/contracts/lib/GyroECLPMath.sol";
import { GyroECLPPool } from "@balancer-labs/v3-pool-gyro/contracts/GyroECLPPool.sol";

import { LPOracleBase } from "./LPOracleBase.sol";

/// @notice Oracle for E-CLP pools.
contract EclpLPOracle is LPOracleBase {
    using FixedPoint for uint256;
    using SignedFixedPoint for int256;
    using SafeCast for *;

    int256 private constant _MIN_PRICE_ECLP = 1e11; // 1e-7 scaled

    /// @notice One of the token prices is too small.
    error TokenPriceTooSmall();

    constructor(
        IVault vault_,
        IGyroECLPPool pool_,
        AggregatorV3Interface[] memory feeds,
        AggregatorV3Interface sequencerUptimeFeed,
        uint256 uptimeResyncWindow,
        uint256 version_
    ) LPOracleBase(vault_, IBasePool(address(pool_)), feeds, sequencerUptimeFeed, uptimeResyncWindow, version_) {
        // solhint-disable-previous-line no-empty-blocks
    }

    /**
     * @notice Computes the total value locked for constant ellipse (ECLP) pools of two assets.
     * @param prices Prices of the two assets according to a market oracle
     * @return tvl Total value of the pool, in the same unit as the price oracles
     */
    function _computeTVL(int256[] memory prices) internal view override returns (uint256) {
        (IGyroECLPPool.EclpParams memory params, IGyroECLPPool.DerivedEclpParams memory derivedParams) = GyroECLPPool(
            address(pool)
        ).getECLPParams();
        (, , , uint256[] memory lastBalancesLiveScaled18) = _vault.getPoolTokenInfo(address(pool));
        uint256 invariant = pool.computeInvariant(lastBalancesLiveScaled18, Rounding.ROUND_DOWN);

        return _computeEclpTvl(params, derivedParams, invariant, prices);
    }

    /**
     * @notice Computes the total value locked for constant ellipse (ECLP) pools of two assets.
     * @dev This computation is resistant to price manipulation within the Balancer pool. Bounds on underlying prices
     * are enforced to make this safe across a range of typical pool parameter combinations. These include typical
     * stable pair configs and the following parameter combinations: alpha in [0.05, 0.999], beta in [1.001, 1.1],
     * relative price range width (beta/alpha-1) >= 10bp, min-curvature price q = 1.0, lambda in [1, 1e8]. This yields
     * a relative error of at most 0.1bp, assuming `invariant / totalSupply >= 2` or total redemption amount at least
     * 1 USD. Please refer to Section 5.4 Consolidated Price Feed, in the Gyro technical documentation, for further
     * details: (https://docs.gyro.finance/gyd/technical-documents.html).
     *
     * @param params ECLP pool parameters
     * @param derivedParams (tau(alpha), tau(beta)) in 18 decimals. The other elements are not used.
     * @param invariant Value of the pool invariant / supply of BPT
     * @param prices Prices of the two assets according to a market oracle
     * @return tvl Total value of the pool, in the same unit as the price oracles
     */
    function _computeEclpTvl(
        IGyroECLPPool.EclpParams memory params,
        IGyroECLPPool.DerivedEclpParams memory derivedParams,
        uint256 invariant,
        int256[] memory prices
    ) internal pure returns (uint256 tvl) {
        if (prices[0] < _MIN_PRICE_ECLP || prices[1] < _MIN_PRICE_ECLP) {
            revert TokenPriceTooSmall();
        }
        (int256 px, int256 py) = (prices[0], prices[1]);

        int256 pxIny = px.divDownMag(py);
        if (pxIny < params.alpha) {
            int256 bP = _removePrecision(
                GyroECLPMath.mulAinv(params, derivedParams.tauBeta).x -
                    GyroECLPMath.mulAinv(params, derivedParams.tauAlpha).x
            );
            tvl = (bP.mulDownMag(px)).toUint256().mulDown(invariant);
        } else if (pxIny > params.beta) {
            int256 bP = _removePrecision(
                GyroECLPMath.mulAinv(params, derivedParams.tauAlpha).y -
                    GyroECLPMath.mulAinv(params, derivedParams.tauBeta).y
            );
            tvl = (bP.mulDownMag(py)).toUint256().mulDown(invariant);
        } else {
            IGyroECLPPool.Vector2 memory vec = GyroECLPMath.mulAinv(params, GyroECLPMath.tau(params, pxIny));
            vec.x = _removePrecision(GyroECLPMath.mulAinv(params, derivedParams.tauBeta).x) - vec.x;
            vec.y = _removePrecision(GyroECLPMath.mulAinv(params, derivedParams.tauAlpha).y) - vec.y;
            tvl = GyroECLPMath.scalarProd(IGyroECLPPool.Vector2(px, py), vec).toUint256().mulDown(invariant);
        }
    }

    /**
     * @dev E-CLP derived parameters are stored with 38 decimals precision. We remove 20 decimals to get 18-decimal
     * precision.
     */
    function _removePrecision(int256 value) private pure returns (int256) {
        return value / 1e20;
    }
}
