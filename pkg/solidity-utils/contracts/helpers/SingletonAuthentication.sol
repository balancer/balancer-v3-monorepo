// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IAuthorizer } from "@balancer-labs/v3-interfaces/contracts/vault/IAuthorizer.sol";

import "./Authentication.sol";

/**
 * @notice Base contract suitable for Singleton contracts (e.g., pool factories) that have permissioned functions.
 * @dev The disambiguator is the contract's own address. This is used in the construction of actionIds for permissioned
 * functions, to avoid conflicts when multiple contracts (or multiple versions of the same contract) use the same
 * function name.
 */
abstract contract SingletonAuthentication is Authentication {
    IVault private immutable _vault;

    // Use the contract's own address to disambiguate action identifiers
    constructor(IVault vault) Authentication(bytes32(uint256(uint160(address(this))))) {
        _vault = vault;
    }

    /**
     * @notice Get the address of the Balancer Vault.
     * @return An interface pointer to the Vault
     */
    function getVault() public view returns (IVault) {
        return _vault;
    }

    /**
     * @notice Get the address of the Authorizer.
     * @return An interface pointer to the Authorizer
     */
    function getAuthorizer() public view returns (IAuthorizer) {
        return getVault().getAuthorizer();
    }

    function _canPerform(bytes32 actionId, address account) internal view override returns (bool) {
        return getAuthorizer().canPerform(actionId, account, address(this));
    }

    function _canPerform(bytes32 actionId, address account, address where) internal view returns (bool) {
        return getAuthorizer().canPerform(actionId, account, where);
    }
}
