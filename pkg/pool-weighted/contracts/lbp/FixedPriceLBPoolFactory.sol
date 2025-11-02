// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPCommon.sol";

import { BasePoolFactory } from "@balancer-labs/v3-pool-utils/contracts/BasePoolFactory.sol";

import { BaseLBPFactory } from "./BaseLBPFactory.sol";
import { LBPoolLib } from "../lib/LBPoolLib.sol";
import { LBPool } from "./LBPool.sol";

/**
 * @notice Factory for Fixed Price LBPools.
 * @dev This is a factory specific to Fixed PriceLBPools, similar to regular Weighted LBPools, but where the token
 * price is fixed throughout the entire sale.
 */
contract FixedPriceLBPoolFactory is BaseLBPFactory, BasePoolFactory {
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

        pool = _createPool(
            lbpCommonParams,
            migrationParams,
            projectTokenRate,
            swapFeePercentage,
            salt,
            false,
            poolCreator
        );
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
        _validateMigration(migrationParams);

        pool = _createPool(
            lbpCommonParams,
            migrationParams,
            projectTokenRate,
            swapFeePercentage,
            salt,
            true,
            poolCreator
        );
    }

    function _createPool(
        LBPCommonParams memory lbpCommonParams,
        MigrationParams memory migrationParams,
        uint256 projectTokenRate,
        uint256 swapFeePercentage,
        bytes32 salt,
        bool hasMigration,
        address poolCreator
    ) internal returns (address pool) {
        if (lbpCommonParams.owner == address(0)) {
            revert InvalidOwner();
        }

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
