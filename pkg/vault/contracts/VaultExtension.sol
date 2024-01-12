// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IVaultExtension } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultExtension.sol";
import { Authentication } from "@balancer-labs/v3-solidity-utils/contracts/helpers/Authentication.sol";
import { VaultStorage } from "./VaultStorage.sol";

/**
 * @dev Bytecode extension for Vault.
 * Has access to the same storage layout as the main vault.
 *
 * The functions in this contract are not meant to be called directly ever. They should just be called by the Vault
 * via delegate calls instead, and any state modification produced by this contract's code will actually target
 * the main Vault's state.
 *
 * The storage of this contract is in practice unused.
 */
contract VaultExtension is IVaultExtension, VaultStorage, Authentication {
    address private immutable _vault;

    constructor(address vault) Authentication(bytes32(uint256(uint160(address(vault))))) {
        _vault = vault;
    }

    function _canPerform(bytes32 actionId, address user) internal view virtual override returns (bool) {
        return _authorizer.canPerform(actionId, user, address(this));
    }
}
