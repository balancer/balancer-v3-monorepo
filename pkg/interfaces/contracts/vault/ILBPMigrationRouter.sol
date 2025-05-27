// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IWeightedPool } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/IWeightedPool.sol";

import { ILBPool } from "../pool-weighted/ILBPool.sol";

/// @notice Interface for migrating liquidity from a Liquidity Bootstrapping Pool (LBP) to new Weighted Pool with custom parameters.
interface ILBPMigrationRouter {
    /**
     * @notice Thrown when trying to migrate liquidity, but the LBP weights are not yet finalized.
     * @param lbp The Liquidity Bootstrapping Pool with unfinalized weights
     */
    error LBPWeightsNotFinalized(ILBPool lbp);

    /**
     * @notice Thrown when the actual input amount of a token is less than required.
     * @param token The token with insufficient input amount
     * @param actualAmount The actual amount of the token provided
     */
    error InsufficientInputAmount(IERC20 token, uint256 actualAmount);

    /**
     * @notice Thrown when the caller is not the owner of the LBP.
     * @param lbpOwner The actual owner of the LBP
     */
    error SenderIsNotLBPOwner(address lbpOwner);

    struct MigrationHookParams {
        ILBPool lbp;
        IWeightedPool weightedPool;
        IERC20[] tokens;
        address sender;
        uint256[] exactAmountsIn;
        uint256 minAddBptAmountOut;
        uint256[] minRemoveAmountsOut;
    }

    struct WeightedPoolParams {
        string name;
        string symbol;
        uint256[] normalizedWeights;
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
     * @param exactAmountsIn The exact amounts of each token to add to the weighted pool
     * @param minAddBptAmountOut Minimum amount of BPT tokens expected to receive
     * @param minRemoveAmountsOut Minimum token amounts expected when removing from the LBP
     * @param params Parameters for creating the new weighted pool
     * @return weightedPool The newly created weighted pool
     * @return bptAmountOut The amount of BPT tokens received from the weighted pool after migration
     */
    function migrateLiquidity(
        ILBPool lbp,
        uint256[] memory exactAmountsIn,
        uint256 minAddBptAmountOut,
        uint256[] memory minRemoveAmountsOut,
        WeightedPoolParams memory params
    ) external returns (IWeightedPool weightedPool, uint256 bptAmountOut);

    /**
     * @notice Simulates a liquidity migration to estimate results before execution.
     * @param lbp Liquidity Bootstrapping Pool
     * @param exactAmountsIn The exact amounts of each token to add to the weighted pool
     * @param sender Sender address
     * @param params Parameters for creating the new weighted pool
     * @return weightedPool The newly created weighted pool
     * @return bptAmountOut The amount of BPT tokens received from the weighted pool after migration
     */
    function queryMigrateLiquidity(
        ILBPool lbp,
        uint256[] memory exactAmountsIn,
        address sender,
        WeightedPoolParams memory params
    ) external returns (IWeightedPool weightedPool, uint256 bptAmountOut);
}
