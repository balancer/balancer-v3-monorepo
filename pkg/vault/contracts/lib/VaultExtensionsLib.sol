// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";

library VaultExtensionsLib {
    function ensureVaultDelegateCall(IVault vault) internal view {
        // If this is a delegate call from the vault, the address of the contract should be the Vault's,
        // not the extension.
        if (address(this) != address(vault)) {
            revert IVaultErrors.NotVaultDelegateCall();
        }
    }
}
