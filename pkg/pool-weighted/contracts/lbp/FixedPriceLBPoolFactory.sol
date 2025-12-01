// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IFixedPriceLBPool } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/IFixedPriceLBPool.sol";
import { LiquidityManagement } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPCommon.sol";

import { BasePoolFactory } from "@balancer-labs/v3-pool-utils/contracts/BasePoolFactory.sol";

import { FixedPriceLBPool } from "./FixedPriceLBPool.sol";
import { BaseLBPFactory } from "./BaseLBPFactory.sol";
import { LBPValidation } from "./LBPValidation.sol";

/**
 * @notice Factory for Fixed Price LBPools.
 * @dev This is a factory specific to Fixed Price LBPools, similar to regular Weighted LBPools, but where the token
 * price is fixed throughout the entire sale.
 */
contract FixedPriceLBPoolFactory is BaseLBPFactory, BasePoolFactory {
    /**
     * @notice Event emitted when a fixed price LBP is deployed.
     * @dev The common factory emits LBPoolCreated (with the pool address and project/reserve tokens). This event gives
     * more detail on this specific LBP configuration. All FixedPrice LBPools are "buy only."
     *
     * @param pool Address of the pool
     * @param owner Address of the pool's owner
     * @param startTime The starting timestamp of the token sale
     * @param endTime  The ending timestamp of the token sale
     * @param projectTokenRate The project token price in terms of the reserve token
     */
    event FixedPriceLBPoolCreated(
        address indexed pool,
        address indexed owner,
        uint256 startTime,
        uint256 endTime,
        uint256 projectTokenRate
    );

    constructor(
        IVault vault,
        uint32 pauseWindowDuration,
        string memory factoryVersion,
        string memory poolVersion,
        address trustedRouter
    )
        BaseLBPFactory(factoryVersion, poolVersion, trustedRouter, address(0)) // no migration router
        BasePoolFactory(vault, pauseWindowDuration, type(FixedPriceLBPool).creationCode)
    {
        // solhint-disable-previous-line no-empty-blocks
    }

    /**
     * @notice Deploys a new `FixedPriceLBPool`.
     * @dev This method does not support native ETH management; WETH needs to be used instead.
     * @param lbpCommonParams The LBP configuration (see ILBPool for the struct definition)
     * @param projectTokenRate The price of the project token in terms of the reserve
     * @param swapFeePercentage Initial swap fee percentage (bound by the WeightedPool range)
     * @param salt The salt value that will be passed to create3 deployment
     * @param poolCreator Address that will be registered as the pool creator, who receives a cut of the protocol fees
     */
    function create(
        LBPCommonParams memory lbpCommonParams,
        uint256 projectTokenRate,
        uint256 swapFeePercentage,
        bytes32 salt,
        address poolCreator
    ) public nonReentrant returns (address pool) {
        if (projectTokenRate == 0) {
            revert IFixedPriceLBPool.InvalidProjectTokenRate();
        }

        if (lbpCommonParams.blockProjectTokenSwapsIn == false) {
            revert IFixedPriceLBPool.TokenSwapsInUnsupported();
        }

        pool = _createPool(lbpCommonParams, projectTokenRate, swapFeePercentage, salt, poolCreator);
    }

    function _createPool(
        LBPCommonParams memory lbpCommonParams,
        uint256 projectTokenRate,
        uint256 swapFeePercentage,
        bytes32 salt,
        address poolCreator
    ) internal returns (address pool) {
        // These validations are duplicated in the pool contract but performed here to surface precise error messages,
        // as create2 would otherwise mask the underlying revert reason.

        lbpCommonParams.startTime = LBPValidation.validateCommonParams(lbpCommonParams);

        FactoryParams memory factoryParams = FactoryParams({
            vault: getVault(),
            trustedRouter: _trustedRouter,
            poolVersion: _poolVersion
        });

        pool = _create(abi.encode(lbpCommonParams, factoryParams, projectTokenRate), salt);

        // Emit type-specific event first
        emit FixedPriceLBPoolCreated(
            pool,
            lbpCommonParams.owner,
            lbpCommonParams.startTime,
            lbpCommonParams.endTime,
            projectTokenRate
        );

        // Only needed for the event.
        MigrationParams memory migrationParams;

        // Emit common events via base helper
        _emitPoolCreatedEvents(
            pool,
            lbpCommonParams.projectToken,
            lbpCommonParams.reserveToken,
            migrationParams,
            false // Migration unsupported for fixed price LBPs
        );

        PoolRoleAccounts memory roleAccounts;

        // This account can change the static swap fee for the pool.
        roleAccounts.swapFeeManager = lbpCommonParams.owner;
        roleAccounts.poolCreator = poolCreator;

        // Only allow proportional add/remove (computeBalance is not implemented).
        LiquidityManagement memory liquidityManagement = getDefaultLiquidityManagement();
        liquidityManagement.disableUnbalancedLiquidity = true;

        _registerPoolWithVault(
            pool,
            _buildTokenConfig(lbpCommonParams.projectToken, lbpCommonParams.reserveToken),
            swapFeePercentage,
            false, // not exempt from protocol fees
            roleAccounts,
            pool, // register the pool itself as the hook contract
            liquidityManagement
        );
    }
}
