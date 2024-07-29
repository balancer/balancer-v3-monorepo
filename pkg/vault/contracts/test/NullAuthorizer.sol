// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "@balancer-labs/v3-interfaces/contracts/vault/IAuthorizer.sol";

/// @notice Dummy Authorizer that always allows access.
contract NullAuthorizer is IAuthorizer {
    /// @inheritdoc IAuthorizer
    function canPerform(bytes32, address, address) external pure override returns (bool) {
        return true;
    }
}
