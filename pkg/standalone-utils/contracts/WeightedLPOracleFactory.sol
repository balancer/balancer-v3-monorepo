// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

import { IWeightedLPOracle } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IWeightedLPOracle.sol";
import { ILPOracleBase } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/ILPOracleBase.sol";
import { IWeightedPool } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/IWeightedPool.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { LPOracleFactoryBase } from "./LPOracleFactoryBase.sol";
import { WeightedLPOracle } from "./WeightedLPOracle.sol";

/**
 * @notice Factory for deploying and managing Weighted Pool oracles.
 */
contract WeightedLPOracleFactory is LPOracleFactoryBase {
    /**
     * @notice A new Weighted Pool oracle was created.
     * @param pool The address of the Weighted Pool
     * @param feeds The array of price feeds for the tokens in the pool
     * @param oracle The address of the deployed oracle
     */
    event WeightedLPOracleCreated(IWeightedPool indexed pool, AggregatorV3Interface[] feeds, IWeightedLPOracle oracle);

    constructor(IVault vault, uint256 oracleVersion) LPOracleFactoryBase(vault, oracleVersion) {
        // solhint-disable-previous-line no-empty-blocks
    }

    function _create(
        IVault vault,
        IBasePool pool,
        AggregatorV3Interface[] memory feeds
    ) internal override returns (ILPOracleBase oracle) {
        IWeightedLPOracle weightedOracle = new WeightedLPOracle(
            vault,
            IWeightedPool(address(pool)),
            feeds,
            _oracleVersion
        );
        oracle = ILPOracleBase(address(weightedOracle));
        emit WeightedLPOracleCreated(IWeightedPool(address(pool)), feeds, weightedOracle);
    }
}
