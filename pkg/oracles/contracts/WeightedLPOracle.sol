// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { IWeightedLPOracle } from "@balancer-labs/v3-interfaces/contracts/oracles/IWeightedLPOracle.sol";
import { ILPOracleBase } from "@balancer-labs/v3-interfaces/contracts/oracles/ILPOracleBase.sol";
import { IWeightedPool } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/IWeightedPool.sol";
import { Rounding } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { LPOracleBase } from "./LPOracleBase.sol";

/// @notice Oracle for weighted pools.
contract WeightedLPOracle is IWeightedLPOracle, LPOracleBase {
    using FixedPoint for uint256;
    using SafeCast for *;


    constructor(
        IVault vault_,
        IWeightedPool pool_,
        AggregatorV3Interface[] memory feeds,
        AggregatorV3Interface sequencerUptimeFeed,
        uint256 uptimeResyncWindow,
        uint256 version_
    ) LPOracleBase(vault_, IBasePool(address(pool_)), feeds, sequencerUptimeFeed, uptimeResyncWindow, version_) {
        // No need to store weights at deployment - they will be fetched dynamically
    }

    /// @inheritdoc LPOracleBase
    function _computeTVL(int256[] memory prices) internal view override returns (uint256 tvl) {
        /**********************************************************************************************
        // We know that the normalized value of each token in the pool is equal:
        // C = (P1 * B1 / W1) = (P2 * B2 / W2) = ... = (Pn * Bn / Wn)
        //
        // Where:
        // n  = number of tokens
        // Pi = market price of token i
        // Bi = balance of token i
        // Wi = normalized weight of token i (sum of all Wi == 1)
        // C  = common normalized value across tokens
        //
        // From this, we can express the balance of token i:
        // Bi = (C * Wi) / Pi
        //
        // The total value locked (TVL) is the sum of all token values:
        // TVL = Σ (Bi * Pi)
        // Substituting Bi:
        // TVL = Σ ((C * Wi / Pi) * Pi) = C * Σ(Wi) = C
        // C = TVL
        //
        // So:
        // Bi = (TVL * Wi) / Pi
        //
        // The invariant of the WeightedPool pool is defined as:
        // k = Π (Bi^Wi)
        //
        // Substituting Bi and using the fact that Σ(Wi) = 1:
        // k = Π ((TVL * Wi / Pi)^Wi)
        //   = TVL^Σ(Wi) * Π((Wi / Pi)^Wi)
        //   = TVL * Π((Wi / Pi)^Wi)
        //
        // Solving for TVL:
        // TVL = k * Π((Pi / Wi)^Wi)
        **********************************************************************************************/

        /**********************************************************************************************
        // invariant                   _____                                                         //
        // wi = weight index i          | |           wi                                             //
        // pi = price index i      k *  | |  (pi/wi) ^   = tvl                                       //
        // k = invariant                                                                             //
        **********************************************************************************************/

        uint256[] memory lastBalancesLiveScaled18 = _vault.getCurrentLiveBalances(address(pool));
        uint256[] memory weights = _getWeights();

        tvl = FixedPoint.ONE;
        for (uint256 i = 0; i < _totalTokens; i++) {
            if (prices[i] <= 0) {
                revert InvalidOraclePrice();
            }

            tvl = tvl.mulDown(prices[i].toUint256().divDown(weights[i]).powDown(weights[i]));
        }

        uint256 k = pool.computeInvariant(lastBalancesLiveScaled18, Rounding.ROUND_UP);

        tvl = tvl.mulDown(k);
    }

    function getWeights() external view returns (uint256[] memory) {
        return _getWeights();
    }

    function _getWeights() internal view returns (uint256[] memory) {
        // Dynamically fetch current normalized weights from the pool
        return IWeightedPool(address(pool)).getNormalizedWeights();
    }
}
