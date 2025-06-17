// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { PoolRoleAccounts } from "../vault/VaultTypes.sol";
import { ILBPool } from "./ILBPool.sol";
import { IWeightedPool } from "./IWeightedPool.sol";

/// @notice Interface for migrating liquidity from an LBP to a new Weighted Pool with custom parameters.
interface ILBPMigrationRouter {
    /**
     * @notice The pool was successfully migrated from an LBP to a new weighted pool.
     * @param lbp The LB Pool that was migrated
     * @param weightedPool The newly created weighted pool
     * @param bptAmountOut The amount of BPT tokens received from the weighted pool after migration
     */
    event PoolMigrated(ILBPool indexed lbp, IWeightedPool weightedPool, uint256 bptAmountOut);

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

    /// @notice The sender is not a trusted factory.
    error SenderIsNotTrustedFactory();

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
