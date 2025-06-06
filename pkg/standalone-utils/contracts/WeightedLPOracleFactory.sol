// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IWeightedLPOracle } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IWeightedLPOracle.sol";
import {
    IWeightedLPOracleFactory
} from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IWeightedLPOracleFactory.sol";
import { SingletonAuthentication } from "@balancer-labs/v3-vault/contracts/SingletonAuthentication.sol";
import { IWeightedPool } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/IWeightedPool.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { WeightedLPOracle } from "./WeightedLPOracle.sol";

contract WeightedLPOracleFactory is IWeightedLPOracleFactory, SingletonAuthentication {
    uint256 internal _oracleVersion;
    mapping(IWeightedPool => IWeightedLPOracle) internal _oracles;

    constructor(IVault vault, uint256 oracleVersion) SingletonAuthentication(vault) {
        _oracleVersion = oracleVersion;
    }

    function create(
        IWeightedPool pool,
        AggregatorV3Interface[] memory feeds
    ) external authenticate returns (IWeightedLPOracle oracle) {
        if (_oracles[pool] != IWeightedLPOracle(address(0))) {
            revert OracleAlreadyExists();
        }

        oracle = new WeightedLPOracle(getVault(), pool, feeds, _oracleVersion);

        _oracles[pool] = oracle;
        emit WeightedLPOracleCreated(pool, oracle);
    }

    function removeOracle(IWeightedPool pool) external authenticate {
        IWeightedLPOracle oracle = _oracles[pool];
        if (oracle == IWeightedLPOracle(address(0))) {
            revert OracleDoesNotExist();
        }

        delete _oracles[pool];

        emit WeightedLPOracleRemoved(pool, oracle);
    }

    function getOracle(IWeightedPool pool) external view returns (IWeightedLPOracle oracle) {
        oracle = _oracles[pool];
    }
}
