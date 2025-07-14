// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

import { IBasePool } from "../vault/IBasePool.sol";
import { ILPOracleBase } from "./ILPOracleBase.sol";

/**
 * @title LP Oracle Factory
 * @notice Factory contract for deploying and managing lp weighted pool oracles.
 */
interface ILPOracleFactoryBase {
    /// @notice Oracle already exists for the given pool.
    error OracleAlreadyExists();

    /**
     * @notice Creates a new oracle for the given pool.
     * @param pool The address of the pool
     * @param feeds The array of price feeds for the tokens in the pool
     * @return oracle The address of the newly created oracle
     */
    function create(IBasePool pool, AggregatorV3Interface[] memory feeds) external returns (ILPOracleBase oracle);

    /**
     * @notice Gets the oracle for the given pool.
     * @param pool The address of the pool
     * @return oracle The address of the oracle for the pool
     */
    function getOracle(IBasePool pool) external view returns (ILPOracleBase oracle);

    /**
     * @notice Checks whether the given oracle was created by this factory.
     * @param oracle The oracle to check
     * @return success True if the oracle was created by this factory; false otherwise
     */
    function isOracleFromFactory(ILPOracleBase oracle) external view returns (bool success);
}
