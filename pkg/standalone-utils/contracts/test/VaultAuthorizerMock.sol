// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IAuthorizer } from "@balancer-labs/v3-interfaces/contracts/vault/IAuthorizer.sol";

contract VaultAuthorizerMock is IAuthorizer {
    address public immutable owner;

    constructor() {
        owner = msg.sender;
    }

    function getAuthorizer() external view returns (IAuthorizer authorizer) {
        return IAuthorizer(address(this));
    }

    /// @inheritdoc IAuthorizer
    function canPerform(bytes32, address account, address) external view returns (bool) {
        return owner == account;
    }

    function canPerform(bytes32, address account) external view returns (bool) {
        return owner == account;
    }
}
