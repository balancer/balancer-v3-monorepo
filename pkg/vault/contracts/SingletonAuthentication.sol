// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IAuthorizer } from "@balancer-labs/v3-interfaces/contracts/vault/IAuthorizer.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { CommonAuthentication } from "./CommonAuthentication.sol";

/**
 * @notice Base contract suitable for Singleton contracts (e.g., pool factories) that have permissioned functions.
 * @dev The disambiguator is the contract's own address. This is used in the construction of actionIds for permissioned
 * functions, to avoid conflicts when multiple contracts (or multiple versions of the same contract) use the same
 * function name.
 */
abstract contract SingletonAuthentication is CommonAuthentication {
    // Use the contract's own address to disambiguate action identifiers.
    constructor(IVault vault) CommonAuthentication(vault, bytes32(uint256(uint160(address(this))))) {
        // solhint-disable-previous-line no-empty-blocks
    }

    /**
     * @notice Get the address of the Balancer Vault.
     * @return vault An interface pointer to the Vault
     */
    function getVault() public view returns (IVault) {
        return _getVault();
    }

    /**
     * @notice Get the address of the Authorizer.
     * @return authorizer An interface pointer to the Authorizer
     */
    function getAuthorizer() public view returns (IAuthorizer) {
        return getVault().getAuthorizer();
    }
}
