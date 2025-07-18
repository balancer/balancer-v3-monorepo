// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

import { ILPOracleBase } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/ILPOracleBase.sol";
import { IStablePool } from "@balancer-labs/v3-interfaces/contracts/pool-stable/IStablePool.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { LPOracleFactoryBase } from "./LPOracleFactoryBase.sol";
import { StableLPOracle } from "./StableLPOracle.sol";

/**
 * @notice Factory for deploying and managing Stable Pool oracles.
 */
contract StableLPOracleFactory is LPOracleFactoryBase {
    /**
     * @notice A new Stable Pool oracle was created.
     * @param pool The address of the Stable Pool
     * @param feeds The array of price feeds for the tokens in the pool
     * @param oracle The address of the deployed oracle
     */
    event StableLPOracleCreated(IStablePool indexed pool, AggregatorV3Interface[] feeds, ILPOracleBase oracle);

    constructor(IVault vault, uint256 oracleVersion) LPOracleFactoryBase(vault, oracleVersion) {
        // solhint-disable-previous-line no-empty-blocks
    }

    function _create(
        IVault vault,
        IBasePool pool,
        AggregatorV3Interface[] memory feeds
    ) internal override returns (ILPOracleBase oracle) {
        oracle = new StableLPOracle(vault, IStablePool(address(pool)), feeds, _oracleVersion);
        emit StableLPOracleCreated(IStablePool(address(pool)), feeds, oracle);
    }
}
