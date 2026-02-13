// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { LBPParams } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPool.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPCommon.sol";

import { BaseLBPFactory } from "./BaseLBPFactory.sol";
import { LBPValidation } from "./LBPValidation.sol";
import { LBPoolLib } from "../lib/LBPoolLib.sol";
import { LBPool } from "./LBPool.sol";

/**
 * @notice Factory for Weighted LBPools.
 * @dev This is a factory specific to LBPools, allowing only two tokens and restricting the LBP to a single token sale,
 * with parameters specified on deployment.
 */
contract LBPoolFactory is BaseLBPFactory {
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
     * @param isSeedless True if this is a seedless LBP (i.e., no reserve token supplied on initialization)
     */
    event WeightedLBPoolCreated(
        address indexed pool,
        address indexed owner,
        bool blockProjectTokenSwapsIn,
        bool hasMigration,
        bool isSeedless
    );

    constructor(
        IVault vault,
        uint32 pauseWindowDuration,
        string memory factoryVersion,
        string memory poolVersion,
        address trustedRouter,
        address migrationRouter
    )
        BaseLBPFactory(
            vault,
            pauseWindowDuration,
            factoryVersion,
            poolVersion,
            trustedRouter,
            migrationRouter,
            type(LBPool).creationCode
        )
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
     * @param poolCreator Address that will be registered as the pool creator, which receives part of the protocol fees
     * @param secondaryHookContract Optional secondary hook contract. (The pool itself is the primary hook.)
     */
    function create(
        LBPCommonParams memory lbpCommonParams,
        LBPParams memory lbpParams,
        uint256 swapFeePercentage,
        bytes32 salt,
        address poolCreator,
        address secondaryHookContract
    ) public nonReentrant returns (address pool) {
        MigrationParams memory migrationParams;

        pool = _createPool(
            lbpCommonParams,
            migrationParams,
            lbpParams,
            swapFeePercentage,
            salt,
            poolCreator,
            secondaryHookContract
        );
    }

    /**
     * @notice Deploys a new `LBPool` with migration.
     * @dev This method does not support native ETH management; WETH needs to be used instead.
     * @param lbpCommonParams The LBP configuration (see ILBPool for the struct definition)
     * @param swapFeePercentage Initial swap fee percentage (bound by the WeightedPool range)
     * @param salt The salt value that will be passed to create3 deployment
     * @param poolCreator Address that will be registered as the pool creator, which receives a cut of the protocol fees
     * @param secondaryHookContract Optional secondary hook contract. (The pool itself is the primary hook.)
     */
    function createWithMigration(
        LBPCommonParams memory lbpCommonParams,
        MigrationParams memory migrationParams,
        LBPParams memory lbpParams,
        uint256 swapFeePercentage,
        bytes32 salt,
        address poolCreator,
        address secondaryHookContract
    ) public nonReentrant returns (address pool) {
        pool = _createPool(
            lbpCommonParams,
            migrationParams,
            lbpParams,
            swapFeePercentage,
            salt,
            poolCreator,
            secondaryHookContract
        );
    }

    function _createPool(
        LBPCommonParams memory lbpCommonParams,
        MigrationParams memory migrationParams,
        LBPParams memory lbpParams,
        uint256 swapFeePercentage,
        bytes32 salt,
        address poolCreator,
        address secondaryHookContract
    ) internal returns (address pool) {
        // These validations are duplicated in the pool contract but performed here to surface precise error messages,
        // as create2 would otherwise mask the underlying revert reason.
        LBPValidation.validateCommonParams(lbpCommonParams);

        LBPoolLib.verifyWeightUpdateParameters(
            lbpParams.projectTokenStartWeight,
            lbpParams.reserveTokenStartWeight,
            lbpParams.projectTokenEndWeight,
            lbpParams.reserveTokenEndWeight
        );

        bool hasMigration = LBPValidation.validateMigrationParams(migrationParams, _migrationRouter);
        bool isSeedless = lbpParams.reserveTokenVirtualBalance > 0;

        FactoryParams memory factoryParams = FactoryParams({
            vault: getVault(),
            trustedRouter: _trustedRouter,
            poolVersion: _poolVersion,
            secondaryHookContract: secondaryHookContract
        });

        pool = _create(abi.encode(lbpCommonParams, migrationParams, lbpParams, factoryParams), salt);

        _registerLBP(pool, lbpCommonParams, swapFeePercentage, poolCreator);

        // Emit type-specific event first.
        emit WeightedLBPoolCreated(
            pool,
            lbpCommonParams.owner,
            lbpCommonParams.blockProjectTokenSwapsIn,
            hasMigration,
            isSeedless
        );

        // Emit common events via base contract helper.
        _emitPoolCreatedEvents(
            pool,
            lbpCommonParams.projectToken,
            lbpCommonParams.reserveToken,
            migrationParams,
            hasMigration
        );
    }
}
