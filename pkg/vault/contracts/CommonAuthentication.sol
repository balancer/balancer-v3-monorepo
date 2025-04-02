// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { Authentication } from "@balancer-labs/v3-solidity-utils/contracts/helpers/Authentication.sol";

/// @dev Base contract for performing access control on external functions within pools.
abstract contract CommonAuthentication is Authentication {
    /// @dev Vault cannot be address(0).
    error VaultNotSet();

    IVault private immutable _vault;

    /// @notice Caller must be the swapFeeManager, if defined. Otherwise, default to governance.
    modifier onlySwapFeeManagerOrGovernance(address pool) {
        address roleAddress = _vault.getPoolRoleAccounts(pool).swapFeeManager;
        _ensureAuthenticatedByExclusiveRole(pool, roleAddress);
        _;
    }

    constructor(IVault vault, bytes32 actionIdDisambiguator) Authentication(actionIdDisambiguator) {
        if (address(vault) == address(0)) {
            revert VaultNotSet();
        }

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

    /// @dev Ensure the sender is the roleAccount, or default to governance if roleAccount is address(0).
    function _ensureAuthenticatedByExclusiveRole(address where, address roleAccount) internal view {
        if (roleAccount == address(0)) {
            // Defer to governance if no role assigned.
            if (_canPerform(getActionId(msg.sig), msg.sender, where) == false) {
                revert SenderNotAllowed();
            }
        } else if (msg.sender != roleAccount) {
            revert SenderNotAllowed();
        }
    }

    /// @dev Ensure the sender is either the role manager, or is authorized by governance (non-exclusive).
    function _ensureAuthenticatedByRole(address where, address roleAccount) internal view {
        // If the sender is not the delegated manager for the role, defer to governance.
        if (msg.sender != roleAccount) {
            if (_canPerform(getActionId(msg.sig), msg.sender, where) == false) {
                revert SenderNotAllowed();
            }
        }
        // (else) if the sender is the delegated manager, proceed.
    }
}
