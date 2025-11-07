// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPCommon.sol";

import { BasePoolFactory } from "@balancer-labs/v3-pool-utils/contracts/BasePoolFactory.sol";

import { FixedPriceLBPool } from "./FixedPriceLBPool.sol";
import { BaseLBPFactory } from "./BaseLBPFactory.sol";
import { LBPValidation } from "./LBPValidation.sol";
import { LBPoolLib } from "../lib/LBPoolLib.sol";

/**
 * @notice Factory for Fixed Price LBPools.
 * @dev This is a factory specific to Fixed Price LBPools, similar to regular Weighted LBPools, but where the token
 * price is fixed throughout the entire sale.
 */
contract FixedPriceLBPoolFactory is BaseLBPFactory, BasePoolFactory {
    /**
     * @notice Event emitted when a fixed price LBP is deployed.
     * @dev The common factory emits LBPoolCreated (with the pool address and project/reserve tokens). This event gives
     * more detail on this specific LBP configuration.
     *
     * @param owner Address of the pool's owner
     * @param startTime The starting timestamp of the token sale
     * @param endTime  The ending timestamp of the token sale
     * @param projectTokenRate The project token price in terms of the reserve token
     * @param blockProjectTokenSwapsIn If true, this is a "buy-only" sale
     * @param hasMigration True if the pool will be migrated after the sale
     */
    event FixedPriceLBPoolCreated(
        address indexed owner,
        uint256 startTime,
        uint256 endTime,
        uint256 projectTokenRate,
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
        BasePoolFactory(vault, pauseWindowDuration, type(FixedPriceLBPool).creationCode)
    {
        // solhint-disable-previous-line no-empty-blocks
    }

    /**
     * @notice Deploys a new `LBPool`.
     * @dev This method does not support native ETH management; WETH needs to be used instead.
     * @param lbpCommonParams The LBP configuration (see ILBPool for the struct definition)
     * @param projectTokenRate The price of the project token in terms of the reserve
     * @param swapFeePercentage Initial swap fee percentage (bound by the WeightedPool range)
     * @param salt The salt value that will be passed to create3 deployment
     * @param poolCreator Address that will be registered as the pool creator, which receives a cut of the protocol fees
     */
    function create(
        LBPCommonParams memory lbpCommonParams,
        uint256 projectTokenRate,
        uint256 swapFeePercentage,
        bytes32 salt,
        address poolCreator
    ) public nonReentrant returns (address pool) {
        MigrationParams memory migrationParams;

        pool = _createPool(lbpCommonParams, migrationParams, projectTokenRate, swapFeePercentage, salt, poolCreator);
    }

    /**
     * @notice Deploys a new `LBPool` with migration.
     * @dev This method does not support native ETH management; WETH needs to be used instead.
     * @param lbpCommonParams The LBP configuration (see ILBPool for the struct definition)
     * @param projectTokenRate The price of the project token in terms of the reserve
     * @param swapFeePercentage Initial swap fee percentage (bound by the WeightedPool range)
     * @param salt The salt value that will be passed to create3 deployment
     * @param poolCreator Address that will be registered as the pool creator, which receives a cut of the protocol fees
     */
    function createWithMigration(
        LBPCommonParams memory lbpCommonParams,
        MigrationParams memory migrationParams,
        uint256 projectTokenRate,
        uint256 swapFeePercentage,
        bytes32 salt,
        address poolCreator
    ) public nonReentrant returns (address pool) {
        pool = _createPool(lbpCommonParams, migrationParams, projectTokenRate, swapFeePercentage, salt, poolCreator);
    }

    function _createPool(
        LBPCommonParams memory lbpCommonParams,
        MigrationParams memory migrationParams,
        uint256 projectTokenRate,
        uint256 swapFeePercentage,
        bytes32 salt,
        address poolCreator
    ) internal returns (address pool) {
        // These validations are duplicated in the pool contract but performed here to surface precise error messages,
        // as create2 would otherwise mask the underlying revert reason.

        LBPValidation.validateCommonParams(lbpCommonParams);

        bool hasMigration = LBPValidation.validateMigrationParams(migrationParams, _migrationRouter);

        address migrationRouterOrZero = hasMigration ? _migrationRouter : address(0);

        FactoryParams memory factoryParams = FactoryParams({
            vault: getVault(),
            trustedRouter: _trustedRouter,
            migrationRouter: migrationRouterOrZero,
            poolVersion: _poolVersion
        });

        pool = _create(abi.encode(lbpCommonParams, migrationParams, factoryParams, projectTokenRate), salt);

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

        emit FixedPriceLBPoolCreated(
            lbpCommonParams.owner,
            lbpCommonParams.startTime,
            lbpCommonParams.endTime,
            projectTokenRate,
            lbpCommonParams.blockProjectTokenSwapsIn,
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
