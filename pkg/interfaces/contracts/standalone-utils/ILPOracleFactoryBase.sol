// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

import { ILPOracleBase } from "./ILPOracleBase.sol";
import { IBasePool } from "../vault/IBasePool.sol";

/// @notice Factory contract for deploying and managing pool oracles.
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
     * @notice Returns a number representing the oracle version.
     * @dev This is a number - not a JSON string like the factory version (and other contracts in the system
     * derived from Version) - because the V3AggregatorInterface for oracles defines a numerical version.
     *
     * @return oracleVersion The oracle version number
     */
    function getOracleVersion() external view returns (uint256 oracleVersion);

    /**
     * @notice Creates a new oracle for the given pool.
     * @dev Note that the caller must ensure that the given `feeds` are correct for the corresponding pool tokens.
     * The contract checks that the array lengths match, but cannot independently verify correctness. See the docs for
     * notes on how to pair feeds (and rate providers) with tokens, as there are many subtleties. Note that mistakes
     * are recoverable; just call create again with the correct values.
     *
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
