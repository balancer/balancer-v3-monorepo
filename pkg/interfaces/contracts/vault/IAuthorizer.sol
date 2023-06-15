// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

interface IAuthorizer {
    /**
     * @dev Returns true if `account` can perform the action described by `actionId` in the contract `where`.
     */
    function canPerform(bytes32 actionId, address account, address where) external view returns (bool);
}
