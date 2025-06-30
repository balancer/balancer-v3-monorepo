// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IWeightedLPOracle } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IWeightedLPOracle.sol";
import {
    IWeightedLPOracleFactory
} from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IWeightedLPOracleFactory.sol";
import { IWeightedPool } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/IWeightedPool.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { SingletonAuthentication } from "@balancer-labs/v3-vault/contracts/SingletonAuthentication.sol";

import { WeightedLPOracle } from "./WeightedLPOracle.sol";

contract WeightedLPOracleFactory is IWeightedLPOracleFactory, SingletonAuthentication {
    uint256 internal _oracleVersion;
    mapping(IWeightedPool => IWeightedLPOracle) internal _oracles;
    mapping(IWeightedLPOracle => bool) internal _isOracleFromFactory;

    constructor(IVault vault, uint256 oracleVersion) SingletonAuthentication(vault) {
        _oracleVersion = oracleVersion;
    }

    /// @inheritdoc IWeightedLPOracleFactory
    function create(
        IWeightedPool pool,
        AggregatorV3Interface[] memory feeds
    ) external returns (IWeightedLPOracle oracle) {
        if (_oracles[pool] != IWeightedLPOracle(address(0))) {
            revert OracleAlreadyExists();
        }

        IVault vault = getVault();
        IERC20[] memory tokens = vault.getPoolTokens(address(pool));

        InputHelpers.ensureInputLengthMatch(tokens.length, feeds.length);

        oracle = new WeightedLPOracle(vault, pool, feeds, _oracleVersion);

        _oracles[pool] = oracle;
        _isOracleFromFactory[oracle] = true;
        emit WeightedLPOracleCreated(pool, oracle);
    }

    /// @inheritdoc IWeightedLPOracleFactory
    function getOracle(IWeightedPool pool) external view returns (IWeightedLPOracle oracle) {
        oracle = _oracles[pool];
    }

    /// @inheritdoc IWeightedLPOracleFactory
    function isOracleFromFactory(IWeightedLPOracle oracle) external view returns (bool success) {
        success = _isOracleFromFactory[oracle];
    }
}
