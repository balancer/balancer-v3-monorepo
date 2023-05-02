// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

import "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/BalancerErrors.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/IBasicAuthorizer.sol";

import "../openzeppelin/EnumerableSet.sol";
import "../helpers/InputHelpers.sol";

contract MockBasicAuthorizer is IBasicAuthorizer {
    using EnumerableSet for EnumerableSet.AddressSet;

    bytes32 public constant override DEFAULT_ADMIN_ROLE = 0x00;

    struct RoleData {
        EnumerableSet.AddressSet members;
        bytes32 adminRole;
    }

    mapping(bytes32 => RoleData) private _roles;

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function hasRole(bytes32 role, address account) public view returns (bool) {
        return _roles[role].members.contains(account);
    }

    function canPerform(
        bytes32 actionId,
        address account,
        address
    ) external view override returns (bool) {
        return hasRole(actionId, account);
    }

    function getRoleMemberCount(bytes32 role) external view override returns (uint256) {
        return _roles[role].members.length();
    }

    function getRoleMember(bytes32 role, uint256 index) external view override returns (address) {
        return _roles[role].members.at(index);
    }

    function getRoleAdmin(bytes32 role) external view override returns (bytes32) {
        return _roles[role].adminRole;
    }

    function grantRolesToMany(bytes32[] memory roles, address[] memory accounts) external {
        InputHelpers.ensureInputLengthMatch(roles.length, accounts.length);
        for (uint256 i = 0; i < roles.length; i++) {
            grantRole(roles[i], accounts[i]);
        }
    }

    function grantRole(bytes32 role, address account) public {
        _require(hasRole(_roles[role].adminRole, msg.sender), Errors.GRANT_SENDER_NOT_ADMIN);
        _grantRole(role, account);
    }

    function revokeRole(bytes32 role, address account) public virtual {
        _require(hasRole(_roles[role].adminRole, msg.sender), Errors.REVOKE_SENDER_NOT_ADMIN);

        _revokeRole(role, account);
    }

    function _grantRole(bytes32 role, address account) private {
        _roles[role].members.add(account);
    }

    function _revokeRole(bytes32 role, address account) private {
        _roles[role].members.remove(account);
    }
}
