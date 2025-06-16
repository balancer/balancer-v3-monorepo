// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

import { IWeightedPool } from "../pool-weighted/IWeightedPool.sol";
import { IWeightedLPOracle } from "./IWeightedLPOracle.sol";

/**
 * @title Weighted LP Oracle Factory
 * @notice Factory contract for deploying and managing lp weighted pool oracles.
 */
interface IWeightedLPOracleFactory {
    /// @notice Oracle already exists for the given pool.
    error OracleAlreadyExists();

    /**
     * @notice New oracle is created for a Weighted Pool.
     * @param pool The address of the Weighted Pool.
     * @param oracle The address of the deployed oracle.
     */
    event WeightedLPOracleCreated(IWeightedPool indexed pool, IWeightedLPOracle oracle);

    /**
     * @notice Creates a new oracle for the given Weighted Pool.
     * @param pool The address of the Weighted Pool.
     * @param feeds The array of price feeds for the tokens in the pool.
     * @return oracle The address of the newly created oracle.
     */
    function create(
        IWeightedPool pool,
        AggregatorV3Interface[] memory feeds
    ) external returns (IWeightedLPOracle oracle);

    /**
     * @notice Gets the oracle for the given Weighted Pool.
     * @param pool The address of the Weighted Pool.
     * @return oracle The address of the oracle for the pool.
     */
    function getOracle(IWeightedPool pool) external view returns (IWeightedLPOracle oracle);

    /**
     * @notice Checks if the given oracle was created by this factory.
     * @param oracle The oracle to check.
     * @return success True if the oracle was created by this factory, false otherwise.
     */
    function isOracleFromFactory(IWeightedLPOracle oracle) external view returns (bool success);
}
