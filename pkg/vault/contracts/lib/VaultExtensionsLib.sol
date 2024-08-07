// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";

/**
 * @notice Ensure functions in extension contracts can only be called through the main Vault.
 * @dev The Vault is composed of three contracts, using the Proxy pattern from OpenZeppelin. `ensureVaultDelegateCall`
 * can be called on the locally stored Vault address by modifiers in extension contracts to ensure that their functions
 * can only be called through the main Vault. Because the storage *layout* is shared (through inheritance of
 * `VaultStorage`), but each contract actually has its own storage, we need to make sure we are always calling in the
 * main Vault context, to avoid referencing storage in the extension contracts.
 */
library VaultExtensionsLib {
    function ensureVaultDelegateCall(IVault vault) internal view {
        // If this is a delegate call from the vault, the address of the contract should be the Vault's,
        // not the extension.
        if (address(this) != address(vault)) {
            revert IVaultErrors.NotVaultDelegateCall();
        }
    }
}
