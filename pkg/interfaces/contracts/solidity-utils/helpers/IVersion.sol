// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

/// @notice Simple interface to retrieve the version of a deployed contract.
interface IVersion {
    /**
     * @notice Return arbitrary text representing the version of a contract.
     * @dev For standard Balancer contracts, returns a JSON representation of the contract version containing name,
     * version number and task ID. See real examples in the deployment repo; local tests just use plain text strings.
     *
     * @return version The version string corresponding to the current deployed contract
     */
    function version() external view returns (string memory);
}
