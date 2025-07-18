// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

import { IBasePool } from "../vault/IBasePool.sol";
import { ILPOracleBase } from "./ILPOracleBase.sol";

/**
 * @notice Factory contract for deploying and managing pool oracles.
 */
interface ILPOracleFactoryBase {
    // @notice Emitted when a the factory is disabled.
    event OracleFactoryDisabled();

    /**
     * @notice Oracle already exists for the given pool.
     * @param pool The pool that already has an oracle
     * @param feeds The array of price feeds for the tokens in the pool
     * @param oracle The oracle that already exists for the pool
     */
    error OracleAlreadyExists(IBasePool pool, AggregatorV3Interface[] feeds, ILPOracleBase oracle);

    /// @notice Oracle factory is disabled.
    error OracleFactoryIsDisabled();

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
     * @param feeds The array of price feeds for the tokens in the pool
     * @return oracle The address of the oracle for the pool
     */
    function getOracle(
        IBasePool pool,
        AggregatorV3Interface[] memory feeds
    ) external view returns (ILPOracleBase oracle);

    /**
     * @notice Checks whether the given oracle was created by this factory.
     * @param oracle The oracle to check
     * @return success True if the oracle was created by this factory; false otherwise
     */
    function isOracleFromFactory(ILPOracleBase oracle) external view returns (bool success);

    /**
     * @notice Disables the oracle factory.
     * @dev A disabled oracle factory cannot create new oracles and cannot be re-enabled. However, already created
     * oracles are still usable.
     */
    function disable() external;
}
