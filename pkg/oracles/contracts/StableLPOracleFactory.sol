// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

import { ILPOracleBase } from "@balancer-labs/v3-interfaces/contracts/oracles/ILPOracleBase.sol";
import { IStablePool } from "@balancer-labs/v3-interfaces/contracts/pool-stable/IStablePool.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { LPOracleFactoryBase } from "./LPOracleFactoryBase.sol";
import { StableLPOracle } from "./StableLPOracle.sol";

/// @notice Factory for deploying and managing Stable Pool oracles.
contract StableLPOracleFactory is LPOracleFactoryBase {
    /**
     * @notice A new Stable Pool oracle was created.
     * @param pool The address of the Stable Pool
     * @param shouldUseBlockTimeForOldestFeedUpdate If true, `latestRoundData` returns the current time for `updatedAt`
     * @param shouldRevertIfVaultUnlocked If true, revert if the Vault is unlocked (i.e., processing a transaction)
     * @param feeds The array of price feeds for the tokens in the pool
     * @param oracle The address of the deployed oracle
     */
    event StableLPOracleCreated(
        IStablePool indexed pool,
        bool shouldUseBlockTimeForOldestFeedUpdate,
        bool shouldRevertIfVaultUnlocked,
        AggregatorV3Interface[] feeds,
        ILPOracleBase oracle
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
        oracle = new StableLPOracle(
            vault,
            IStablePool(address(pool)),
            feeds,
            _sequencerUptimeFeed,
            _uptimeResyncWindow,
            shouldUseBlockTimeForOldestFeedUpdate,
            shouldRevertIfVaultUnlocked,
            _oracleVersion
        );
        emit StableLPOracleCreated(
            IStablePool(address(pool)),
            shouldUseBlockTimeForOldestFeedUpdate,
            shouldRevertIfVaultUnlocked,
            feeds,
            oracle
        );
    }
}
