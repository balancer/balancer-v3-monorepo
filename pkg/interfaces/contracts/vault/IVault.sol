// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "../solidity-utils/helpers/IAuthentication.sol";
import "../vault/IAuthorizer.sol";

/**
 * @dev Will eventually be the full external interface for the Vault core contract - still under construction.
 * No external or public methods exist in the contract that don't override one of these declarations.
 */
interface IVault is IAuthentication {
    /**
     * @dev Returns the Vault's Authorizer.
     */
    function getAuthorizer() external view returns (IAuthorizer);

    /**
     * @dev Sets a new Authorizer for the Vault. The caller must be allowed by the current Authorizer to do this.
     *
     * Emits an `AuthorizerChanged` event.
     */
    function setAuthorizer(IAuthorizer newAuthorizer) external;

    /**
     * @dev Emitted when a new authorizer is set by `setAuthorizer`.
     */
    event AuthorizerChanged(IAuthorizer indexed newAuthorizer);
}
