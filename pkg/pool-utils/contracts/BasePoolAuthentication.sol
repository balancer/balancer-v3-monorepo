// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { Authentication } from "@balancer-labs/v3-solidity-utils/contracts/helpers/Authentication.sol";

/// @dev Base contract for performing access control on external functions within pools.
abstract contract BasePoolAuthentication is Authentication {
    IVault private immutable _vault;

    /**
     * @dev Allow only the swapFeeManager or an authenticated user to call the function.
     */
    modifier onlySwapFeeManagerOrAuthentication(address pool) {
        _ensureSwapFeeManagerOrAuthentication(pool);
        _;
    }

    /**
     * @dev Pools should use the pool factory as the disambiguator passed into the base Authentication contract.
     * Otherwise, permissions would conflict if different pools reused function names.
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

    /// @dev Ensure the sender is the swapFeeManager, or default to governance if there is no manager.
    function _ensureSwapFeeManagerOrAuthentication(address pool) internal view {
        address swapFeeManager = _vault.getPoolRoleAccounts(pool).swapFeeManager;

        if (swapFeeManager == address(0)) {
            if (_canPerform(getActionId(msg.sig), msg.sender, pool) == false) {
                revert SenderNotAllowed();
            }
        } else if (swapFeeManager != msg.sender) {
            revert SenderNotAllowed();
        }
    }
}
