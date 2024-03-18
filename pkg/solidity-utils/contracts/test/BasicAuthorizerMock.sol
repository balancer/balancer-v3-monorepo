// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.20;

import "@balancer-labs/v3-interfaces/contracts/vault/IAuthorizer.sol";

contract BasicAuthorizerMock is IAuthorizer {
    // Simple, to avoid bringing in EnumerableSet, etc.
    mapping(bytes32 => mapping(address => bool)) private _roles;

    /// @inheritdoc IAuthorizer
    function canPerform(bytes32 role, address account, address) external view override returns (bool) {
        return hasRole(role, account);
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
}
