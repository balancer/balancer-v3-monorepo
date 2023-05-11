// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

import "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";


contract BasicVaultMock is IVault {
    IAuthorizer private _authorizer;

    constructor(IAuthorizer authorizer) {
        _authorizer = authorizer;
    }

    /// @inheritdoc IVault
    function getAuthorizer() external view override returns (IAuthorizer) {
        return _authorizer;
    }

    /// @inheritdoc IVault
    function setAuthorizer(IAuthorizer newAuthorizer) external override {
        _authorizer = newAuthorizer;

        emit AuthorizerChanged(newAuthorizer);
    }

    /// @inheritdoc IAuthentication
    function getActionId(uint16 chainId, bytes4 selector) public view override returns (bytes32) {
        return keccak256(abi.encodePacked(bytes32(bytes20(address(this))), chainId, selector));
    }
}
