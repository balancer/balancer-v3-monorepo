// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IVersion.sol";

/// @notice Retrieves a contract's version set at creation time from storage.
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
