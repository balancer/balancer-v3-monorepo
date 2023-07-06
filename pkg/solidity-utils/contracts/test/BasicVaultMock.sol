// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { IAuthorizer } from "@balancer-labs/v3-interfaces/contracts/vault/IAuthorizer.sol";

contract BasicVaultMock is IAuthentication, IAuthorizer {
    IAuthorizer private _authorizer;

    constructor(IAuthorizer authorizer) {
        _authorizer = authorizer;
    }

    function getAuthorizer() external view returns (IAuthorizer) {
        return _authorizer;
    }

    function setAuthorizer(IAuthorizer newAuthorizer) external {
        _authorizer = newAuthorizer;

        emit AuthorizerChanged(newAuthorizer);
    }

    /// @inheritdoc IAuthentication
    function getActionId(uint16 chainId, bytes4 selector) public view override returns (bytes32) {
        return keccak256(abi.encodePacked(bytes32(bytes20(address(this))), chainId, selector));
    }

    function canPerform(bytes32, address, address) external pure returns (bool) {
        return true;
    }
}
