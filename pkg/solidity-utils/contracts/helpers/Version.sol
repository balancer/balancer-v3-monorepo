// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IVersion.sol";

/**
 * @notice Retrieves a contract's version from storage.
 * @dev The version is set at deployment time and cannot be changed. It would be immutable, but immutable strings
 * are not yet supported.
 *
 * Contracts like factories and pools should have versions. These typically take the form of JSON strings containing
 * detailed information about the deployment. For instance:
 *
 * `{name: 'ChildChainGaugeFactory', version: 2, deployment: '20230316-child-chain-gauge-factory-v2'}`
 */
contract Version is IVersion {
    string private _version;

    constructor(string memory version_) {
        _setVersion(version_);
    }

    function version() external view returns (string memory) {
        return _version;
    }

    /// @dev Internal setter that allows this contract to be used in proxies.
    function _setVersion(string memory newVersion) internal {
        _version = newVersion;
    }
}
