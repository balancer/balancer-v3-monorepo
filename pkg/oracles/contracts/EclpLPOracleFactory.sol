// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

import { IGyroECLPPool } from "@balancer-labs/v3-interfaces/contracts/pool-gyro/IGyroECLPPool.sol";
import { ILPOracleBase } from "@balancer-labs/v3-interfaces/contracts/oracles/ILPOracleBase.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { LPOracleFactoryBase } from "./LPOracleFactoryBase.sol";
import { EclpLPOracle } from "./EclpLPOracle.sol";

/// @notice Factory for deploying and managing ECLP Pool oracles.
contract EclpLPOracleFactory is LPOracleFactoryBase {
    /**
     * @notice A new ECLP Pool oracle was created.
     * @param pool The address of the ECLP Pool
     * @param feeds The array of price feeds for the tokens in the pool
     * @param oracle The address of the deployed oracle
     */
    event EclpLPOracleCreated(IGyroECLPPool indexed pool, AggregatorV3Interface[] feeds, ILPOracleBase oracle);

    constructor(
        IVault vault,
        AggregatorV3Interface sequencerUptimeFeed,
        uint256 resyncWindow,
        string memory factoryVersion,
        uint256 oracleVersion
    ) LPOracleFactoryBase(vault, sequencerUptimeFeed, resyncWindow, factoryVersion, oracleVersion) {
        // solhint-disable-previous-line no-empty-blocks
    }

    function _create(
        IVault vault,
        IBasePool pool,
        AggregatorV3Interface[] memory feeds
    ) internal override returns (ILPOracleBase oracle) {
        oracle = new EclpLPOracle(
            vault,
            IGyroECLPPool(address(pool)),
            feeds,
            _sequencerUptimeFeed,
            _uptimeResyncWindow,
            _oracleVersion
        );
        emit EclpLPOracleCreated(IGyroECLPPool(address(pool)), feeds, oracle);
    }
}
