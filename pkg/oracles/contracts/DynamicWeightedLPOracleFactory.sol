// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

import { IWeightedLPOracle } from "@balancer-labs/v3-interfaces/contracts/oracles/IWeightedLPOracle.sol";
import { IWeightedPool } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/IWeightedPool.sol";
import { ILPOracleBase } from "@balancer-labs/v3-interfaces/contracts/oracles/ILPOracleBase.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { DynamicWeightedLPOracle } from "./DynamicWeightedLPOracle.sol";
import { LPOracleFactoryBase } from "./LPOracleFactoryBase.sol";

/**
 * @notice Factory for deploying and managing Dynamic Weighted Pool oracles.
 * @dev DynamicWeightedLPOracles fetch weights from the pool at query time, so this factory should be used for pools
 * with variable weights, such as Liquidity Bootstrapping Pools (LBPs). It is not suitable for fixed-weight pools;
 * use `WeightedLPOracleFactory` for those instead.
 */
contract DynamicWeightedLPOracleFactory is LPOracleFactoryBase {
    /**
     * @notice A new Dynamic Weighted Pool oracle was created.
     * @param pool The address of the Weighted Pool
     * @param shouldUseBlockTimeForOldestFeedUpdate If true, `latestRoundData` returns the current time for `updatedAt`
     * @param shouldRevertIfVaultUnlocked If true, revert if the Vault is unlocked (i.e., processing a transaction)
     * @param feeds The array of price feeds for the tokens in the pool
     * @param oracle The address of the deployed oracle
     */
    event DynamicWeightedLPOracleCreated(
        IWeightedPool indexed pool,
        bool shouldUseBlockTimeForOldestFeedUpdate,
        bool shouldRevertIfVaultUnlocked,
        AggregatorV3Interface[] feeds,
        IWeightedLPOracle oracle
    );

    constructor(
        IVault vault,
        AggregatorV3Interface sequencerUptimeFeed,
        uint256 uptimeResyncWindow,
        string memory factoryVersion,
        uint256 oracleVersion
    ) LPOracleFactoryBase(vault, sequencerUptimeFeed, uptimeResyncWindow, factoryVersion, oracleVersion) {
        // solhint-disable-previous-line no-empty-blocks
    }

    function _create(
        IVault vault,
        IBasePool pool,
        bool shouldUseBlockTimeForOldestFeedUpdate,
        bool shouldRevertIfVaultUnlocked,
        AggregatorV3Interface[] memory feeds
    ) internal override returns (ILPOracleBase oracle) {
        IWeightedLPOracle weightedOracle = new DynamicWeightedLPOracle(
            vault,
            IWeightedPool(address(pool)),
            feeds,
            _sequencerUptimeFeed,
            _uptimeResyncWindow,
            shouldUseBlockTimeForOldestFeedUpdate,
            shouldRevertIfVaultUnlocked,
            _oracleVersion
        );
        oracle = ILPOracleBase(address(weightedOracle));
        emit DynamicWeightedLPOracleCreated(
            IWeightedPool(address(pool)),
            shouldUseBlockTimeForOldestFeedUpdate,
            shouldRevertIfVaultUnlocked,
            feeds,
            weightedOracle
        );
    }
}
