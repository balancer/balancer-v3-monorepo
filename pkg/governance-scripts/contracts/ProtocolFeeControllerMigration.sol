// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { IBasicAuthorizer } from "@balancer-labs/v3-interfaces/contracts/governance-scripts/IBasicAuthorizer.sol";
import { IProtocolFeeController } from "@balancer-labs/v3-interfaces/contracts/vault/IProtocolFeeController.sol";
import { PoolRoleAccounts, PoolConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { SingletonAuthentication } from "@balancer-labs/v3-vault/contracts/SingletonAuthentication.sol";
import { ProtocolFeeController } from "@balancer-labs/v3-vault/contracts/ProtocolFeeController.sol";
import {
    ReentrancyGuardTransient
} from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/ReentrancyGuardTransient.sol";

/**
 * @notice Migrate to a ProtocolFeeController with extra events and infrastructure for future migrations.
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
 * When all pools have been migrated, call `finalizeMigration` to disable further migration, update the address in the
 * Vault, and renounce all permissions. While `migratePools` is permissionless, this call must be permissioned to
 * prevent premature termination in case multiple transactions are required to migrate all the pools.
 *
 * Associated with `20250221-protocol-fee-controller-migration` (fork test only).
 */
contract ProtocolFeeControllerMigration is ReentrancyGuardTransient, SingletonAuthentication {
    IProtocolFeeController public immutable oldFeeController;
    IProtocolFeeController public newFeeController;

    IVault public immutable vault;

    // IAuthorizer with interface for granting/revoking roles.
    IBasicAuthorizer internal immutable _authorizer;

    // Set when the operation is complete and all permissions have been renounced.
    bool internal _finalized;

    // Set after the global percentages have been transferred (on the first call to `migratePools`).
    bool internal _globalPercentagesMigrated;

    /**
     * @notice Attempt to deploy this contract with invalid parameters.
     * @dev ProtocolFeeController contracts return the address of the Vault they were deployed with. Ensure that both
     * the old and new controllers reference the same vault.
     */
    error InvalidFeeController();

    /// @notice Migration can only be performed once.
    error AlreadyMigrated();

    constructor(IVault _vault, IProtocolFeeController _newFeeController) SingletonAuthentication(_vault) {
        oldFeeController = _vault.getProtocolFeeController();

        // Ensure valid fee controllers. Also ensure that we are not trying to operate on the current fee controller.
        if (_newFeeController.vault() != _vault || _newFeeController == oldFeeController) {
            revert InvalidFeeController();
        }

        vault = _vault;
        newFeeController = _newFeeController;

        _authorizer = IBasicAuthorizer(address(vault.getAuthorizer()));
    }

    /**
     * @notice Check whether migration has been completed.
     * @dev It can only be done once.
     * @return isComplete True if `finalizeMigration` has been called.
     */
    function isMigrationComplete() public view returns (bool) {
        return _finalized;
    }

    /**
     * @notice Migrate pools from the old fee controller to the new one.
     * @dev This can be called multiple times, if there are too many pools for a single transaction. Note that the
     * first time this is called, it will migrate the global fee percentages, then proceed with the first set of pools.
     *
     * @param pools The set of pools to be migrated in this call
     */
    function migratePools(address[] memory pools) external virtual nonReentrant {
        if (isMigrationComplete()) {
            revert AlreadyMigrated();
        }

        // Migrate the global percentages only once, before the first set of pools.
        if (_globalPercentagesMigrated == false) {
            _globalPercentagesMigrated = true;

            _migrateGlobalPercentages();
        }

        // This more complex migration allows for pool creators and overrides, and uses the new features in the second
        // deployment of the `ProtocolFeeController`.
        //
        // At the end of this process, governance must still withdraw any leftover protocol fees from the old
        // controller (i.e., that have been collected but not withdrawn). Pool creators likewise would still need to
        // withdraw any leftover pool creator fees from the old controller.
        for (uint256 i = 0; i < pools.length; ++i) {
            // This function is not in the public interface.
            ProtocolFeeController(address(newFeeController)).migratePool(pools[i]);
        }
    }

    function finalizeMigration() external virtual authenticate {
        if (isMigrationComplete()) {
            revert AlreadyMigrated();
        }

        _finalized = true;

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
