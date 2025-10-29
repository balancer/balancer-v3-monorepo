// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { LBPCommonParams, MigrationParams } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPCommon.sol";
import { PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { LBPParams, FactoryParams } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPool.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { BasePoolFactory } from "@balancer-labs/v3-pool-utils/contracts/BasePoolFactory.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { BaseLBPFactory } from "./BaseLBPFactory.sol";
import { LBPoolLib } from "../lib/LBPoolLib.sol";
import { LBPool } from "./LBPool.sol";

/**
 * @notice Factory for Weighted LBPools.
 * @dev This is a factory specific to LBPools, allowing only two tokens and restricting the LBP to a single token sale,
 * with parameters specified on deployment.
 */
contract LBPoolFactory is BaseLBPFactory, BasePoolFactory {
    constructor(
        IVault vault,
        uint32 pauseWindowDuration,
        string memory factoryVersion,
        string memory poolVersion,
        address trustedRouter,
        address migrationRouter
    )
        BaseLBPFactory(factoryVersion, poolVersion, trustedRouter, migrationRouter)
        BasePoolFactory(vault, pauseWindowDuration, type(LBPool).creationCode)
    {
        // solhint-disable-previous-line no-empty-blocks
    }

    /**
     * @notice Deploys a new `LBPool`.
     * @dev This method does not support native ETH management; WETH needs to be used instead.
     * @param lbpCommonParams The LBP configuration (see ILBPool for the struct definition)
     * @param lbpParams The LBP configuration (see ILBPool for the struct definition)
     * @param swapFeePercentage Initial swap fee percentage (bound by the WeightedPool range)
     * @param salt The salt value that will be passed to create3 deployment
     * @param poolCreator Address that will be registered as the pool creator, which receives a cut of the protocol fees
     */
    function create(
        LBPCommonParams memory lbpCommonParams,
        LBPParams memory lbpParams,
        uint256 swapFeePercentage,
        bytes32 salt,
        address poolCreator
    ) public nonReentrant returns (address pool) {
        MigrationParams memory migrationParams;

        pool = _createPool(lbpCommonParams, migrationParams, lbpParams, swapFeePercentage, salt, false, poolCreator);
    }

    /**
     * @notice Deploys a new `LBPool` with migration.
     * @dev This method does not support native ETH management; WETH needs to be used instead.
     * @param lbpCommonParams The LBP configuration (see ILBPool for the struct definition)
     * @param swapFeePercentage Initial swap fee percentage (bound by the WeightedPool range)
     * @param salt The salt value that will be passed to create3 deployment
     * @param poolCreator Address that will be registered as the pool creator, which receives a cut of the protocol fees
     */
    function createWithMigration(
        LBPCommonParams memory lbpCommonParams,
        MigrationParams memory migrationParams,
        LBPParams memory lbpParams,
        uint256 swapFeePercentage,
        bytes32 salt,
        address poolCreator
    ) public nonReentrant returns (address pool) {
        pool = _createPool(lbpCommonParams, migrationParams, lbpParams, swapFeePercentage, salt, true, poolCreator);
    }

    function _createPool(
        LBPCommonParams memory lbpCommonParams,
        MigrationParams memory migrationParams,
        LBPParams memory lbpParams,
        uint256 swapFeePercentage,
        bytes32 salt,
        bool hasMigration,
        address poolCreator
    ) internal returns (address pool) {
        if (lbpCommonParams.owner == address(0)) {
            revert InvalidOwner();
        }

        PoolRoleAccounts memory roleAccounts;

        // This account can change the static swap fee for the pool.
        roleAccounts.swapFeeManager = lbpCommonParams.owner;
        roleAccounts.poolCreator = poolCreator;

        // Validate weight parameters and temporal constraints prior to deployment.
        // This validation is duplicated in the pool contract but performed here to surface precise error messages,
        // as create2 would otherwise mask the underlying revert reason. We don't need the return value.

        // wake-disable-next-line unchecked-return-value
        LBPoolLib.verifyWeightUpdateParameters(
            lbpCommonParams.startTime,
            lbpCommonParams.endTime,
            lbpParams.projectTokenStartWeight,
            lbpParams.reserveTokenStartWeight,
            lbpParams.projectTokenEndWeight,
            lbpParams.reserveTokenEndWeight
        );

        // If there is no migration, the migration parameters don't need to be validated.
        if (hasMigration) {
            uint256 totalTokenWeight = migrationParams.migrationWeightProjectToken +
                migrationParams.migrationWeightReserveToken;
            if (
                (totalTokenWeight != FixedPoint.ONE ||
                    migrationParams.migrationWeightProjectToken == 0 ||
                    migrationParams.migrationWeightReserveToken < _MIN_RESERVE_TOKEN_MIGRATION_WEIGHT)
            ) {
                revert InvalidMigrationWeights();
            }

            // Must be a valid percentage, and doesn't make sense to be zero if there is a migration.
            if (
                migrationParams.bptPercentageToMigrate > FixedPoint.ONE || migrationParams.bptPercentageToMigrate == 0
            ) {
                revert InvalidBptPercentageToMigrate();
            }

            // Cannot go over the maximum duration. There is no minimum duration, but it shouldn't be zero.
            if (
                migrationParams.lockDurationAfterMigration > _MAX_BPT_LOCK_DURATION ||
                migrationParams.lockDurationAfterMigration == 0
            ) {
                revert InvalidBptLockDuration();
            }
        }

        address migrationRouterOrZero = hasMigration ? _migrationRouter : address(0);

        FactoryParams memory factoryParams = FactoryParams({
            vault: getVault(),
            trustedRouter: _trustedRouter,
            migrationRouter: migrationRouterOrZero,
            poolVersion: _poolVersion
        });

        pool = _create(abi.encode(lbpCommonParams, migrationParams, lbpParams, factoryParams), salt);

        emit LBPoolCreated(pool, lbpCommonParams.projectToken, lbpCommonParams.reserveToken);

        if (hasMigration) {
            emit MigrationParamsSet(
                pool,
                migrationParams.lockDurationAfterMigration,
                migrationParams.bptPercentageToMigrate,
                migrationParams.migrationWeightProjectToken,
                migrationParams.migrationWeightReserveToken
            );
        }

        _registerPoolWithVault(
            pool,
            _buildTokenConfig(lbpCommonParams.projectToken, lbpCommonParams.reserveToken),
            swapFeePercentage,
            false, // not exempt from protocol fees
            roleAccounts,
            pool, // register the pool itself as the hook contract
            getDefaultLiquidityManagement()
        );
    }
}
