// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

/// @notice Simple interface to retrieve the version of pools deployed by a pool factory.
interface IPoolVersion {
    /**
     * @notice Returns a JSON representation of the deployed pool version containing name, version number and task ID.
     * @dev This is typically only useful in complex Pool deployment schemes, where multiple subsystems need to know about
     * each other. Note that this value will only be updated at factory creation time.
     */
    function getPoolVersion() external view returns (string memory);
}
