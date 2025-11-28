// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { LBPParams } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPool.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPCommon.sol";

import { BasePoolFactory } from "@balancer-labs/v3-pool-utils/contracts/BasePoolFactory.sol";

import { BaseLBPFactory } from "./BaseLBPFactory.sol";
import { LBPValidation } from "./LBPValidation.sol";
import { LBPoolLib } from "../lib/LBPoolLib.sol";
import { LBPool } from "./LBPool.sol";

/**
 * @notice Factory for Weighted LBPools.
 * @dev This is a factory specific to LBPools, allowing only two tokens and restricting the LBP to a single token sale,
 * with parameters specified on deployment.
 */
contract LBPoolFactory is BaseLBPFactory, BasePoolFactory {
    /**
     * @notice Event emitted when a standard weighted LBPool is deployed.
     * @dev The common factory emits LBPoolCreated (with the pool address and project/reserve tokens). This event gives
     * more detail on this specific LBP configuration. The pool also emits a `GradualWeightUpdateScheduled` event with
     * the starting and ending times and weights.
     *
     * @param pool Address of the pool
     * @param owner Address of the pool's owner
     * @param blockProjectTokenSwapsIn If true, this is a "buy-only" sale
     * @param hasMigration True if the pool will be migrated after the sale
     */
    event WeightedLBPoolCreated(
        address indexed pool,
        address indexed owner,
        bool blockProjectTokenSwapsIn,
        bool hasMigration
    );

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

        pool = _createPool(lbpCommonParams, migrationParams, lbpParams, swapFeePercentage, salt, poolCreator);
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
        pool = _createPool(lbpCommonParams, migrationParams, lbpParams, swapFeePercentage, salt, poolCreator);
    }

    function _createPool(
        LBPCommonParams memory lbpCommonParams,
        MigrationParams memory migrationParams,
        LBPParams memory lbpParams,
        uint256 swapFeePercentage,
        bytes32 salt,
        address poolCreator
    ) internal returns (address pool) {
        // These validations are duplicated in the pool contract but performed here to surface precise error messages,
        // as create2 would otherwise mask the underlying revert reason.

        lbpCommonParams.startTime = LBPValidation.validateCommonParams(lbpCommonParams);

        LBPoolLib.verifyWeightUpdateParameters(
            lbpParams.projectTokenStartWeight,
            lbpParams.reserveTokenStartWeight,
            lbpParams.projectTokenEndWeight,
            lbpParams.reserveTokenEndWeight
        );

        bool hasMigration = LBPValidation.validateMigrationParams(migrationParams, _migrationRouter);

        address migrationRouterOrZero = hasMigration ? _migrationRouter : address(0);

        FactoryParams memory factoryParams = FactoryParams({
            vault: getVault(),
            trustedRouter: _trustedRouter,
            migrationRouter: migrationRouterOrZero,
            poolVersion: _poolVersion
        });

        pool = _create(abi.encode(lbpCommonParams, migrationParams, lbpParams, factoryParams), salt);

        // Emit type-specific event first.
        emit WeightedLBPoolCreated(pool, lbpCommonParams.owner, lbpCommonParams.blockProjectTokenSwapsIn, hasMigration);

        // Emit common events via base contract helper.
        _emitPoolCreatedEvents(
            pool,
            lbpCommonParams.projectToken,
            lbpCommonParams.reserveToken,
            migrationParams,
            hasMigration
        );

        PoolRoleAccounts memory roleAccounts;

        // This account can change the static swap fee for the pool.
        roleAccounts.swapFeeManager = lbpCommonParams.owner;
        roleAccounts.poolCreator = poolCreator;

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
