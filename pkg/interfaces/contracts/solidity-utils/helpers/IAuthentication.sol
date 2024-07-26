// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

/// @notice Simple interface for permissioned calling of external functions.
interface IAuthentication {
    /// @dev The sender does not have permission to call a function.
    error SenderNotAllowed();

    /**
     * @dev Returns the action identifier associated with the external function described by `selector`.
     * @param selector The 4-byte selector of the permissioned function
     * @return actionId The computed actionId
     */
    function getActionId(bytes4 selector) external view returns (bytes32);
}
