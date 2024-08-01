// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "@balancer-labs/v3-interfaces/contracts/vault/IAuthorizer.sol";

contract BasicAuthorizerMock is IAuthorizer {
    // Simple, to avoid bringing in EnumerableSet, etc.
    mapping(bytes32 => mapping(address => bool)) private _roles;

    // Could generalize better, but wanted to make minimal changes.
    mapping(bytes32 => mapping(address => mapping(address => bool))) private _specificRoles;

    /// @inheritdoc IAuthorizer
    function canPerform(bytes32 role, address account, address where) external view returns (bool) {
        return hasSpecificRole(role, account, where) || hasRole(role, account);
    }

    function grantRole(bytes32 role, address account) external {
        _roles[role][account] = true;
    }

    function revokeRole(bytes32 role, address account) external {
        _roles[role][account] = false;
    }

    function hasRole(bytes32 role, address account) public view returns (bool) {
        return _roles[role][account];
    }

    // Functions for targeted permissions

    function grantSpecificRole(bytes32 role, address account, address where) external {
        _specificRoles[role][account][where] = true;
    }

    function revokeSpecificRole(bytes32 role, address account, address where) external {
        _specificRoles[role][account][where] = false;
    }

    function hasSpecificRole(bytes32 role, address account, address where) public view returns (bool) {
        return _specificRoles[role][account][where];
    }
}
