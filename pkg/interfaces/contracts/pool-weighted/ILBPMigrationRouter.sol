// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { PoolRoleAccounts } from "../vault/VaultTypes.sol";
import { ILBPool } from "./ILBPool.sol";
import { IWeightedPool } from "./IWeightedPool.sol";

/// @notice Interface for migrating liquidity from an LBP to a new Weighted Pool with custom parameters.
interface ILBPMigrationRouter {
    /**
     * @notice Migration was set up for the LBP.
     * @param lbp The LB Pool
     * @param bptLockDuration The duration for which the BPT tokens will be locked
     * @param shareToMigrate The share of the pool to migrate
     * @param newWeight0 The new weight for token0 in the weighted pool
     * @param newWeight1 The new weight for token1 in the weighted pool
     */
    event MigrationSetup(
        ILBPool indexed lbp,
        uint256 bptLockDuration,
        uint256 shareToMigrate,
        uint256 newWeight0,
        uint256 newWeight1
    );

    /**
     * @notice The pool was successfully migrated from an LBP to a new weighted pool.
     * @param lbp The LB Pool that was migrated
     * @param weightedPool The newly created weighted pool
     * @param bptAmountOut The amount of BPT tokens received from the weighted pool after migration
     */
    event PoolMigrated(ILBPool indexed lbp, IWeightedPool weightedPool, uint256 bptAmountOut);

    /**
     * @notice A time-locked amount of tokens was locked for a specific owner.
     * @param owner The address of the owner of the locked tokens
     * @param token The address of the token that was locked
     * @param amount The amount of tokens that were locked
     * @param unlockTimestamp The timestamp when the locked tokens can be unlocked
     */
    event AmountLocked(address indexed owner, address token, uint256 amount, uint256 unlockTimestamp);

    /**
     * @notice A contract returned from the Balancer Contract Registry is not active.
     * @param contractName The name of the contract that is not active
     */
    error ContractIsNotActiveInRegistry(string contractName);

    /**
     * @notice `migrateLiquidity` was called before the sale completed.
     * @param lbp The Liquidity Bootstrapping Pool with unfinalized weights
     */
    error LBPWeightsNotFinalized(ILBPool lbp);

    /// @notice The caller is not the owner of the LBP.
    error SenderIsNotLBPOwner();

    /// @notice Migration was already set up for the LBP.
    error MigrationAlreadySetup();

    /// @notice The LBP does not have a migration set up.
    error MigrationDoesNotExist();

    /// @notice The weights provided for migration are invalid.
    error InvalidMigrationWeights();

    /// @notice The LBP is not registered in the Vault.
    error PoolNotRegistered();

    /// @notice The LBP has already started, migration cannot be set up.
    error LBPAlreadyStarted(uint256 startTime);

    /// @notice Locked amount not found for the given index.
    error TimeLockedAmountNotFound(uint256 index);

    /// @notice The locked amount is not yet unlocked.
    error TimeLockedAmountNotUnlockedYet(uint256 index, uint256 unlockTimestamp);

    struct MigrationParams {
        uint64 bptLockDuration;
        uint64 shareToMigrate;
        uint64 weight0;
        uint64 weight1;
    }

    struct MigrationHookParams {
        ILBPool lbp;
        IWeightedPool weightedPool;
        IERC20[] tokens;
        address sender;
        address excessReceiver;
        MigrationParams migrationParams;
    }

    struct WeightedPoolParams {
        string name;
        string symbol;
        PoolRoleAccounts roleAccounts;
        uint256 swapFeePercentage;
        address poolHooksContract;
        bool enableDonation;
        bool disableUnbalancedLiquidity;
        bytes32 salt;
    }

    struct TimeLockedAmount {
        address token;
        uint256 amount;
        uint256 unlockTimestamp;
    }

    /**
     * @notice Returns the time-locked amount of tokens for a specific owner and index.
     * @param owner The address of the owner of the time-locked amount
     * @param index The index of the time-locked amount
     * @return TimeLockedAmount The owner's time-locked amount
     */
    function getTimeLockedAmount(address owner, uint256 index) external view returns (TimeLockedAmount memory);

    /**
     * @notice Returns the count of time-locked amounts for a specific owner.
     * @param owner The address of the owner of the time-locked amounts
     * @return uint256 The count of time-locked amounts for the owner
     */
    function getTimeLockedAmountsCount(address owner) external view returns (uint256);

    /**
     * @notice Unlock the locked tokens for the caller.
     * @param timeLockedIndexes The indexes of the time-locked amounts to unlock
     */
    function unlockTokens(uint256[] memory timeLockedIndexes) external;

    /**
     * @notice Checks if the migration is set up for a given LBP.
     * @param lbp Liquidity Bootstrapping Pool
     * @return bool True if migration is set up, false otherwise
     */
    function isMigrationSetup(ILBPool lbp) external view returns (bool);

    /**
     * @notice Returns the migration parameters for a given LBP.
     * @param lbp Liquidity Bootstrapping Pool
     * @return MigrationParams The migration parameters for the LBP
     */
    function getMigrationParams(ILBPool lbp) external view returns (MigrationParams memory);

    /**
     * @notice Sets up migration for the LBP
     * @param lbp Liquidity Bootstrapping Pool
     * @param bptLockDuration Duration for which BPT tokens will be locked
     * @param shareToMigrate Percentage of shares to migrate
     * @param newWeight0 New weight for the first token in the weighted pool
     * @param newWeight1 New weight for the second token in the weighted pool
     */
    function setupMigration(
        ILBPool lbp,
        uint256 bptLockDuration,
        uint256 shareToMigrate,
        uint256 newWeight0,
        uint256 newWeight1
    ) external;

    /**
     * @notice Migrates liquidity from an LBP to a new weighted pool with custom parameters.
     * @param lbp Liquidity Bootstrapping Pool
     * @param excessReceiver Address to receive excess tokens after migration
     * @param params Parameters for creating the new weighted pool
     * @return weightedPool The newly created weighted pool
     * @return bptAmountOut The amount of BPT tokens received from the weighted pool after migration
     */
    function migrateLiquidity(
        ILBPool lbp,
        address excessReceiver,
        WeightedPoolParams memory params
    ) external returns (IWeightedPool weightedPool, uint256 bptAmountOut);

    /**
     * @notice Simulates a liquidity migration to estimate results before execution.
     * @param lbp Liquidity Bootstrapping Pool
     * @param sender Sender address
     * @param params Parameters for creating the new weighted pool
     * @return bptAmountOut The amount of BPT tokens received from the weighted pool after migration
     */
    function queryMigrateLiquidity(
        ILBPool lbp,
        address sender,
        address excessReceiver,
        WeightedPoolParams memory params
    ) external returns (uint256 bptAmountOut);
}
