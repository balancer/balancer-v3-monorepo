// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { Authentication } from "./Authentication.sol";

/// @dev Base contract for performing access control on external functions within pools.
abstract contract CommonAuthentication is Authentication {
    IVault private immutable _vault;

    /**
     * @dev Allow only the swapFeeManager or governance user to call the function.
     */
    /// @notice Caller must be the swapFeeManager, if defined. Otherwise, default to governance.
    modifier onlySwapFeeManagerOrGovernance(address pool) {
        address roleAddress = _vault.getPoolRoleAccounts(pool).swapFeeManager;
        _ensureAuthenticatedByExclusiveRole(pool, roleAddress);
        _;
    }

    constructor(IVault vault, bytes32 actionIdDisambiguator) Authentication(actionIdDisambiguator) {
        _vault = vault;
    }

    function _getVault() internal view returns (IVault) {
        return _vault;
    }

    // Access control is delegated to the Authorizer in the `_canPerform` functions.
    function _canPerform(bytes32 actionId, address user) internal view override returns (bool) {
        return _vault.getAuthorizer().canPerform(actionId, user, address(this));
    }

    function _canPerform(bytes32 actionId, address account, address where) internal view returns (bool) {
        return _vault.getAuthorizer().canPerform(actionId, account, where);
    }

    /// @dev Ensure the sender is the roleAddress, or default to governance if roleAddress is address(0).
    function _ensureAuthenticatedByExclusiveRole(address pool, address roleAddress) internal view {
        if (roleAddress == address(0)) {
            // Defer to governance if no role assigned.
            if (_canPerform(getActionId(msg.sig), msg.sender, pool) == false) {
                revert SenderNotAllowed();
            }
        } else if (msg.sender != roleAddress) {
            revert SenderNotAllowed();
        }
    }
}
