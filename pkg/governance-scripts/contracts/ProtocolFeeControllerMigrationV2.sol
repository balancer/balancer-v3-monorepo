// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { IProtocolFeeController } from "@balancer-labs/v3-interfaces/contracts/vault/IProtocolFeeController.sol";
import { PoolRoleAccounts, PoolConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { SingletonAuthentication } from "@balancer-labs/v3-vault/contracts/SingletonAuthentication.sol";
import { ProtocolFeeController } from "@balancer-labs/v3-vault/contracts/ProtocolFeeController.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { ProtocolFeeControllerMigration } from "./ProtocolFeeControllerMigration.sol";
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
 * When all pools have been migrated, call `finalizeMigration` to disable further migration, update the address in the
 * Vault, and renounce all permissions. While `migratePools` is permissionless, this call must be permissioned to
 * prevent premature termination in case multiple transactions are required to migrate all the pools.
 *
 * Associated with `20250221-protocol-fee-controller-migration` (fork test only).
 */
contract ProtocolFeeControllerMigrationV2 is ProtocolFeeControllerMigration, SingletonAuthentication {
    using FixedPoint for uint256;

    // Set after the global percentages have been transferred (on the first call to `migratePools`).
    bool internal _globalPercentagesMigrated;

    // ActionId for permission required in `migratePools`.
    bytes32 internal _migrationRole;

    /// @notice Cannot call the base contract migration; it is invalid for this migration.
    error WrongMigrationVersion();

    constructor(
        IVault _vault,
        IProtocolFeeController _newFeeController
    ) ProtocolFeeControllerMigration(_vault, _newFeeController) SingletonAuthentication(_vault) {
        _migrationRole = IAuthentication(address(newFeeController)).getActionId(
            ProtocolFeeController.migratePool.selector
        );

        // Grant permission required in `migratePools`.
        _authorizer.grantRole(_migrationRole, address(this));
    }

    /**
     * @notice Migrate pools from the old fee controller to the new one.
     * @dev THis can be called multiple times, if there are too many pools for a single transaction. Note that the
     * first time this is called, it will migrate the global fee percentages, then proceed with the first set of pools.
     *
     * @param pools The set of pools to be migrated in this call
     */
    function migratePools(address[] memory pools) external nonReentrant {
        if (_finalized) {
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

    function finalizeMigration() external authenticate {
        if (_finalized) {
            revert AlreadyMigrated();
        }

        _finalized = true;

        // Remove permission to migrate pools.
        _authorizer.renounceRole(_migrationRole, address(this));

        // Update the fee controller in the Vault.
        _migrateFeeController();

        // Revoke all permissions.
        _authorizer.renounceRole(_authorizer.DEFAULT_ADMIN_ROLE(), address(this));
    }

    /// @inheritdoc ProtocolFeeControllerMigration
    function migrateFeeController(address[] memory) external pure override {
        // The one-step migration does not work in this version, with pool creators and overrides.
        revert WrongMigrationVersion();
    }
}
