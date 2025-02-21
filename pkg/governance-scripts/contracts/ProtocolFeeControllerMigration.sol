// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { IBasicAuthorizer } from "@balancer-labs/v3-interfaces/contracts/governance-scripts/IBasicAuthorizer.sol";
import { IProtocolFeeController } from "@balancer-labs/v3-interfaces/contracts/vault/IProtocolFeeController.sol";
import { PoolRoleAccounts, PoolConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { ProtocolFeeController } from "@balancer-labs/v3-vault/contracts/ProtocolFeeController.sol";
import {
    ReentrancyGuardTransient
} from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/ReentrancyGuardTransient.sol";

/**
 * @notice Migrate from the original ProtocolFeeController to one with extra events.
 * @dev These events enable tracking pool protocol fees under all circumstances (in particular, when protocol fees are
 * initially turned off). It also adds some infrastructure that makes future migrations easier, and removes redundant
 * poolCreator storage.
 *
 * This simple migration assumes:
 * 1) There are no pools with pool creators
 * 2) There are no pools with protocol fee exemptions or overrides
 * 3) Migrating the complete list of pools can be done in a single transaction.
 *
 * These simplifications enable simply calling `migrateFeeController` once with the complete list of pools.
 *
 * After the migration, the Vault will point to the new fee controller, and any collection thereafter will go there.
 * If there are any residual fee amounts in the old fee controller (i.e., that were collected but not withdrawn),
 * governance will still need to withdraw from the old fee controller. Otherwise, no further interaction with the old
 * controller is necessary.
 *
 * Associated with `20250221-protocol-fee-controller-migration`.
 */
contract ProtocolFeeControllerMigration is ReentrancyGuardTransient {
    IProtocolFeeController public immutable oldFeeController;
    IProtocolFeeController public newFeeController;

    IVault public immutable vault;

    // IAuthorizer with interface for granting/revoking roles.
    IBasicAuthorizer internal immutable _authorizer;

    // Set when the operation is complete and all permissions have been renounced.
    bool internal _finalized;

    /**
     * @notice Attempt to deploy this contract with invalid parameters.
     * @dev ProtocolFeeController contracts return the address of the Vault they were deployed with. Ensure that both
     * the old and new controllers reference the same vault.
     */
    error InvalidFeeController();

    /// @notice Migration can only be performed once.
    error AlreadyMigrated();

    /*constructor(IVault _vault, IProtocolFeeController _newFeeController) {
        oldFeeController = _vault.getProtocolFeeController();

        // Ensure valid fee controllers. Also ensure that we are not trying to operate on the current fee controller.
        if (_newFeeController.vault() != _vault || _newFeeController == oldFeeController) {
            revert InvalidFeeController();
        }

        vault = _vault;
        newFeeController = _newFeeController;

        _authorizer = IBasicAuthorizer(address(vault.getAuthorizer()));
    }*/

    // Temporary constructor used for fork testing.
    constructor(IVault _vault) {
        oldFeeController = _vault.getProtocolFeeController();

        vault = _vault;

        _authorizer = IBasicAuthorizer(address(vault.getAuthorizer()));
    }

    // Temporary - delete after fork test. Run this before `migrateFeeController`.
    function setNewFeeController(IProtocolFeeController _newFeeController) external {
        newFeeController = _newFeeController;
    }
    /**
     * @notice Permissionless migration function.
     * @dev Call this with the full set of pools to perform the migration. After this runs, the Vault will point to the
     * new fee controller, which will have a copy of all the relevant state from the old controller. Also, all
     * permissions will be revoked, and the contract will be disabled.
     *
     * @param pools The complete set of pools to migrate
     */
    function migrateFeeController(address[] memory pools) external virtual nonReentrant {
        if (_finalized) {
            revert AlreadyMigrated();
        }

        _finalized = true;

        _migrateGlobalPercentages();

        // This simple migration assumes that:
        // 1) There are no pool creators, so no state related to pool creator fees (and no fees to be withdrawn).
        // 2) There are no protocol fee exempt pools or governance overrides
        //    (i.e., all override flags are false, and all pool fees match current global values).
        //
        // At the end of this process, since there are no pool creators, token balances should all be zero, unless
        // there are "left over" protocol fees that have been collected but not withdrawn. Governance would then
        // still have to withdraw from the old fee controller.
        //
        // For future migrations, when we might have pool creator fees, the pool creators would still need to withdraw
        // them from the old controller themselves.
        for (uint256 i = 0; i < pools.length; ++i) {
            address pool = pools[i];

            // Set pool-specific values. This assumes there are no fee exempt pools or overrides.
            newFeeController.updateProtocolSwapFeePercentage(pool);
            newFeeController.updateProtocolYieldFeePercentage(pool);
        }

        // Update the fee controller in the Vault.
        _migrateFeeController();

        // Revoke all permissions.
        _authorizer.renounceRole(_authorizer.DEFAULT_ADMIN_ROLE(), address(this));
    }

    function _migrateGlobalPercentages() internal {
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
