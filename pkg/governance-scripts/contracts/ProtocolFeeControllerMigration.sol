// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { IProtocolFeeController } from "@balancer-labs/v3-interfaces/contracts/vault/IProtocolFeeController.sol";
import { PoolRoleAccounts, PoolConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { SingletonAuthentication } from "@balancer-labs/v3-vault/contracts/SingletonAuthentication.sol";
import { ProtocolFeeController } from "@balancer-labs/v3-vault/contracts/ProtocolFeeController.sol";
import {
    ReentrancyGuardTransient
} from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/ReentrancyGuardTransient.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { IBasicAuthorizer } from "./IBasicAuthorizer.sol";

/**
 * @notice Migrate from the original ProtocolFeeController to one with extra events.
 * @dev These events enable tracking pool protocol fees under all circumstances (in particular, when protocol fees are
 * initially turned off).
 *
 * After deployment, call `migratePools` as many times as necessary. The list must be generated externally, as pools
 * are not iterable on-chain. The batch interface allows an unlimited number of pools to be migrated; it's possible
 * there might be too many to migrate in a single call.
 *
 * The first time `migratePools` is called, the contract will first copy the global (pool-independent data). This could
 * be done in a separate stage, but we're trying to keep the contract simple, vs. duplicating the staging coordinator
 * system of v2 just yet.
 *
 * When all pools have been migrated, call `finalizeMigration` to disable further migration and renounce all
 * permissions. While `migratePools` is permissionless, this call must be permissioned to prevent premature
 * termination in case multiple transactions are required to migrate all the pools.
 *
 * Associated with `20250221-protocol-fee-controller-migration`.
 */
contract ProtocolFeeControllerMigration is SingletonAuthentication, ReentrancyGuardTransient {
    using FixedPoint for uint256;

    IProtocolFeeController public immutable oldFeeController;
    IProtocolFeeController public immutable newFeeController;

    // Recipient of protocol fees (from the old controller).
    address public immutable feeRecipient;

    IVault public immutable vault;

    // IAuthorizer with interface for granting/revoking roles.
    IBasicAuthorizer internal immutable _authorizer;

    // Set when the operation is complete and all permissions have been renounced.
    bool private _finalized;

    /**
     * @notice Attempt to deploy this contract with invalid parameters.
     * @dev ProtocolFeeController contracts return the address of the Vault they were deployed with. Ensure that both
     * the old and new controllers reference the same vault.
     */
    error InvalidFeeController();

    /// @notice Migration can only be performed once.
    error AlreadyMigrated();

    /// @notice Ensure protocol fees aren't getting burned.
    error InvalidFeeRecipient();

    constructor(
        IVault _vault,
        IProtocolFeeController _oldFeeController,
        IProtocolFeeController _newFeeController,
        address _feeRecipient
    ) SingletonAuthentication(_oldFeeController.vault()) {
        IVault oldControllerVault = _oldFeeController.vault();

        // Ensure valid fee controllers.
        if (_newFeeController.vault() != oldControllerVault || _vault != oldControllerVault) {
            revert InvalidFeeController();
        }

        if (_feeRecipient == address(0)) {
            revert InvalidFeeRecipient();
        }

        vault = _vault;
        oldFeeController = _oldFeeController;
        newFeeController = _newFeeController;
        feeRecipient = _feeRecipient;

        _authorizer = IBasicAuthorizer(address(vault.getAuthorizer()));
    }

    function migrateFeeController(address[] memory pools) external nonReentrant {
        if (_finalized) {
            revert AlreadyMigrated();
        }

        _finalized = true;

        _migrateGlobalPercentages();

        // Allow withdrawing protocol fees from the old controller to the new controller (during pool migrations).
        bytes32 withdrawProtocolFeesRole = IAuthentication(address(oldFeeController)).getActionId(
            IProtocolFeeController.withdrawProtocolFees.selector
        );

        _authorizer.grantRole(withdrawProtocolFeesRole, address(this));

        // This simple migration assumes that:
        // 1) There are no pool creators, so no state related to pool creator fees (and no fees to be withdrawn).
        // 2) There are no protocol fee exempt pools or governance overrides
        //    (i.e., all override flags are false, and all pool fees match current global values).
        //
        // At the end of this process, since there are no pool creators, token balances should all be zero.
        // This allows for some fee collection after deployment of this contract and before migration, which is
        // why the migrator forces collection and withdraws them, so that no further interaction with the old
        // fee controller is necessary after migration.
        //
        // For future migrations, when we might have pool creator fees, the pool creators would still need to withdraw
        // them from the old controller themselves.
        for (uint256 i = 0; i < pools.length; ++i) {
            address pool = pools[i];

            // Force collection of fees, and withdraw them to the fee recipient.
            // Pool creators will still need to withdraw from the old pool controller.
            oldFeeController.collectAggregateFees(pool);
            oldFeeController.withdrawProtocolFees(pool, feeRecipient);

            // Set pool-specific values. This assumes there are no fee exempt pools or overrides.
            newFeeController.updateProtocolSwapFeePercentage(pool);
            newFeeController.updateProtocolYieldFeePercentage(pool);
        }

        // Remove all permissions.
        _authorizer.renounceRole(withdrawProtocolFeesRole, address(this));

        // Update the fee controller in the Vault.
        _migrateFeeController();

        _authorizer.renounceRole(_authorizer.DEFAULT_ADMIN_ROLE(), address(this));
    }

    function _migrateGlobalPercentages() private {
        // Grant global fee percentage permissions to set on new controller.
        bytes32 swapFeeRole = IAuthentication(address(newFeeController)).getActionId(
            IProtocolFeeController.setGlobalProtocolSwapFeePercentage.selector
        );

        bytes32 yieldFeeRole = IAuthentication(address(newFeeController)).getActionId(
            IProtocolFeeController.setGlobalProtocolYieldFeePercentage.selector
        );

        _authorizer.grantRole(swapFeeRole, address(this));
        _authorizer.grantRole(yieldFeeRole, address(this));

        // Copy percentages to new controller.
        uint256 globalSwapFeePercentage = oldFeeController.getGlobalProtocolSwapFeePercentage();
        uint256 globalYieldFeePercentage = oldFeeController.getGlobalProtocolYieldFeePercentage();

        newFeeController.setGlobalProtocolSwapFeePercentage(globalSwapFeePercentage);
        newFeeController.setGlobalProtocolYieldFeePercentage(globalYieldFeePercentage);

        // Revoke permissions.
        _authorizer.renounceRole(swapFeeRole, address(this));
        _authorizer.renounceRole(yieldFeeRole, address(this));
    }

    function _migrateFeeController() internal {
        bytes32 setFeeControllerRole = IAuthentication(address(vault)).getActionId(
            IVaultAdmin.setProtocolFeeController.selector
        );

        _authorizer.grantRole(setFeeControllerRole, address(this));

        vault.setProtocolFeeController(newFeeController);

        _authorizer.renounceRole(setFeeControllerRole, address(this));
    }
}
