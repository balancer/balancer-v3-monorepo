// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

interface IAuthentication {
    /// @dev Error indicating that the sender does not have permission to call a function.
    error SenderNotAllowed();

    /// @dev Returns the action identifier associated with the external function described by `selector`.
    function getActionId(bytes4 selector) external view returns (bytes32);
}
