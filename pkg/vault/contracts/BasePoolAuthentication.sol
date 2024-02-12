// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { Authentication } from "@balancer-labs/v3-solidity-utils/contracts/helpers/Authentication.sol";

/**
 * @dev Building block for performing access control on external functions within pools.
 *
 * This contract is used via the `authenticate` modifier (or the `_authenticateCaller` function), which can be applied
 * to external functions to only make them callable by authorized accounts.
 *
 * Derived contracts must implement the `_canPerform` function, which holds the actual access control logic.
 */
abstract contract BasePoolAuthentication is Authentication {
    IVault private immutable _vault;

    /**
     * @dev The main purpose of the `actionIdDisambiguator` is to prevent accidental function selector collisions in
     * multi contract systems.
     *
     * There are two main uses for it:
     *  - if the contract is a singleton, any unique identifier can be used to make the associated action identifiers
     *    unique. The contract's own address is a good option.
     *  - if the contract belongs to a family that shares action identifiers for the same functions, an identifier
     *    shared by the entire family (and no other contract) should be used instead.
     *
     * Pools are an example of the second type, so we should use the pool factory as the disambiguator; otherwise,
     * permissions would conflict if different pools reused function names.
     */
    constructor(IVault vault, address factory) Authentication(bytes32(uint256(uint160(factory)))) {
        _vault = vault;
    }

    // Access control is delegated to the Authorizer in the `_canPerform` functions.

    function _canPerform(bytes32 actionId, address user) internal view override returns (bool) {
        return _vault.getAuthorizer().canPerform(actionId, user, address(this));
    }

    function _canPerform(bytes32 actionId, address account, address where) internal view returns (bool) {
        return _vault.getAuthorizer().canPerform(actionId, account, where);
    }
}
