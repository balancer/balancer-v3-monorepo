// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

interface IAuthorizer {
    /**
     * @notice Returns true if `account` can perform the action described by `actionId` in the contract `where`.
     * @param actionId Identifier for the action to be performed
     * @param account Account trying to perform the action
     * @param where Target contract for the action
     * @return True if the action is permitted
     */
    function canPerform(bytes32 actionId, address account, address where) external view returns (bool);
}
