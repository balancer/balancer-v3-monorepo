// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { ILPOracleBase } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/ILPOracleBase.sol";
import { IGyroECLPPool } from "@balancer-labs/v3-interfaces/contracts/pool-gyro/IGyroECLPPool.sol";
import { Rounding } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { SignedFixedPoint } from "@balancer-labs/v3-pool-gyro/contracts/lib/SignedFixedPoint.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { GyroECLPPool } from "@balancer-labs/v3-pool-gyro/contracts/GyroECLPPool.sol";

import { LPOracleBase } from "./LPOracleBase.sol";

/**
 * @notice Oracle for weighted pools.
 */
contract EclpLPOracle is LPOracleBase {
    using FixedPoint for uint256;
    using SignedFixedPoint for int256;
    using SafeCast for *;

    uint256 internal constant ONEHALF = 0.5e18;
    int256 internal constant MIN_PRICE_ECLP = 1e11; // 1e-7 scaled

    // One of the token prices is too small.
    error TOKEN_PRICES_TOO_SMALL();

    constructor(
        IVault vault_,
        IGyroECLPPool pool_,
        AggregatorV3Interface[] memory feeds,
        uint256 version_
    ) LPOracleBase(vault_, IBasePool(address(pool_)), feeds, version_) {
        // solhint-disable-previous-line no-empty-blocks
    }

    /// @inheritdoc ILPOracleBase
    function calculateTVL(int256[] memory prices) public view override returns (uint256) {
        (IGyroECLPPool.EclpParams memory params, IGyroECLPPool.DerivedEclpParams memory derivedParams) = GyroECLPPool(
            address(pool)
        ).getECLPParams();
        (, , , uint256[] memory lastBalancesLiveScaled18) = _vault.getPoolTokenInfo(address(pool));
        uint256 invariant = pool.computeInvariant(lastBalancesLiveScaled18, Rounding.ROUND_DOWN);

        return calculateECLPTvl(params, derivedParams, invariant, prices);
    }

    /**
     * @notice Calculates the value of BPT for constant ellipse (ECLP) pools of two assets.
     * @dev This calculation is robust to price manipulation within the Balancer pool.
     * Bounds on underlying prices are enforced to make this safe across a range of typical pool
     * parameter combinations, see `ECLP_precision_analysis_iteration.sage`. These include typical
     * stable pair configs and the following parameter combinations: alpha in [0.05, 0.999], beta
     * in [1.001, 1.1], relative price range width (beta/alpha-1) >= 10bp, min-curvature price q =
     * 1.0, lambda in [1, 1e8]. This yields relative error at most 0.1bp, assuming
     * invariantDivSupply >= 2 or total redemption amount at least 1 USD.
     *
     * @param params ECLP pool parameters
     * @param derivedParams (tau(alpha), tau(beta)) in 18 decimals. The other elements are not used.
     * @param invariant Value of the pool invariant / supply of BPT
     * @param prices Prices of the two assets according to a market oracle
     * @return tvl Total value of the pool, in the same unit as the price oracles
     */
    function calculateECLPTvl(
        IGyroECLPPool.EclpParams memory params,
        IGyroECLPPool.DerivedEclpParams memory derivedParams,
        uint256 invariant,
        int256[] memory prices
    ) internal pure returns (uint256 tvl) {
        /**********************************************************************************************
        // When alpha < p_x/p_y < beta:                                                              //
        //                L   / / e_x A^{-1} tau(beta) \     -1     / p_x \  \   / p_x \             //
        //   bptPrice =  --- | |                        | - A^  tau|  ---- |  | |       |            //
        //                S   \ \ e_y A^{-1} tau(alpha) /           \ p_y  /  /  \ p_y  /            //
        // When p_x/p_y < alpha:                                                                     //
        //      bptPrice = L/S * p_x ( e_x A^{-1} tau(beta) - e_x A^{-1} tau(alpha) )                //
        // When p_x/p_y > beta:                                                                      //
        //      bptPrice = L/S * p_y (e_y A^{-1} tau(alpha) - e_y A^{-1} tau(beta) )                 //
        **********************************************************************************************/
        if (prices[0] < MIN_PRICE_ECLP || prices[1] < MIN_PRICE_ECLP) {
            revert TOKEN_PRICES_TOO_SMALL();
        }
        (int256 px, int256 py) = (prices[0], prices[1]);

        int256 pxIny = px.divDownMag(py);
        if (pxIny < params.alpha) {
            int256 bP = _removePrecision(
                mulAinv(params, derivedParams.tauBeta).x - mulAinv(params, derivedParams.tauAlpha).x
            );
            tvl = (bP.mulDownMag(px)).toUint256().mulDown(invariant);
        } else if (pxIny > params.beta) {
            int256 bP = _removePrecision(
                mulAinv(params, derivedParams.tauAlpha).y - mulAinv(params, derivedParams.tauBeta).y
            );
            tvl = (bP.mulDownMag(py)).toUint256().mulDown(invariant);
        } else {
            IGyroECLPPool.Vector2 memory vec = mulAinv(params, tau(params, pxIny));
            vec.x = _removePrecision(mulAinv(params, derivedParams.tauBeta).x) - vec.x;
            vec.y = _removePrecision(mulAinv(params, derivedParams.tauAlpha).y) - vec.y;
            tvl = scalarProdDown(IGyroECLPPool.Vector2(px, py), vec).toUint256().mulDown(invariant);
        }
    }

    /**
     * @dev E-CLP derived parameters are stored with 38 decimals precision. We remove 20 decimals to get 18 decimals precision.
     */
    function _removePrecision(int256 value) private pure returns (int256) {
        return value / 1e20;
    }

    ///////////////////////////////////////////////////////////////////////////////////////
    // The following functions and structs copied over from ECLP math library
    // Can't easily inherit because of different Solidity versions

    // Scalar product of IGyroECLPPool.Vector2 objects
    function scalarProdDown(
        IGyroECLPPool.Vector2 memory t1,
        IGyroECLPPool.Vector2 memory t2
    ) internal pure returns (int256 ret) {
        ret = t1.x.mulDownMag(t2.x) + t1.y.mulDownMag(t2.y);
    }

    /** @dev Calculate A^{-1}t where A^{-1} is given in Section 2.2
     *  This is rotating and scaling the circle into the ellipse */

    function mulAinv(
        IGyroECLPPool.EclpParams memory params,
        IGyroECLPPool.Vector2 memory t
    ) internal pure returns (IGyroECLPPool.Vector2 memory tp) {
        tp.x = t.x.mulDownMag(params.lambda).mulDownMag(params.c) + t.y.mulDownMag(params.s);
        tp.y = -t.x.mulDownMag(params.lambda).mulDownMag(params.s) + t.y.mulDownMag(params.c);
    }

    /** @dev Given price px on the transformed ellipse, maps to the corresponding point on the untransformed normalized circle
     *  px = price of asset x in terms of asset y */
    function tau(
        IGyroECLPPool.EclpParams memory params,
        int256 px
    ) internal pure returns (IGyroECLPPool.Vector2 memory tpp) {
        return eta(zeta(params, px));
    }

    /** @dev Given price on a circle, gives the normalized corresponding point on the circle centered at the origin
     *  pxc = price of asset x in terms of asset y (measured on the circle)
     *  Notice that the eta function does not depend on Params */
    function eta(int256 pxc) internal pure returns (IGyroECLPPool.Vector2 memory tpp) {
        int256 z = FixedPoint.powDown(FixedPoint.ONE + (pxc.mulDownMag(pxc).toUint256()), ONEHALF).toInt256();
        tpp = eta(pxc, z);
    }

    /** @dev Calculates eta in more efficient way if the square root is known and input as second arg */
    function eta(int256 pxc, int256 z) internal pure returns (IGyroECLPPool.Vector2 memory tpp) {
        tpp.x = pxc.divDownMag(z);
        tpp.y = SignedFixedPoint.ONE.divDownMag(z);
    }

    /** @dev Given price px on the transformed ellipse, get the untransformed price pxc on the circle
     *  px = price of asset x in terms of asset y */
    function zeta(IGyroECLPPool.EclpParams memory params, int256 px) internal pure returns (int256 pxc) {
        IGyroECLPPool.Vector2 memory nd = mulA(params, IGyroECLPPool.Vector2(-SignedFixedPoint.ONE, px));
        return -nd.y.divDownMag(nd.x);
    }

    /** @dev Calculate A t where A is given in Section 2.2
     *  This is reversing rotation and scaling of the ellipse (mapping back to circle) */

    function mulA(
        IGyroECLPPool.EclpParams memory params,
        IGyroECLPPool.Vector2 memory tp
    ) internal pure returns (IGyroECLPPool.Vector2 memory t) {
        t.x = params.c.mulDownMag(tp.x).divDownMag(params.lambda) - params.s.mulDownMag(tp.y).divDownMag(params.lambda);
        t.y = params.s.mulDownMag(tp.x) + params.c.mulDownMag(tp.y);
    }
}
