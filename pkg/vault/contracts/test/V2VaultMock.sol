// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IAuthorizer } from "@balancer-labs/v3-interfaces/contracts/vault/IAuthorizer.sol";
import { Iv2Vault } from "@balancer-labs/v3-interfaces/contracts/vault/Iv2Vault.sol";

contract V2VaultMock is Iv2Vault {
    IAuthorizer private _authorizer;

    constructor(IAuthorizer authorizer) {
        _authorizer = authorizer;
    }

    function getAuthorizer() external view override returns (IAuthorizer) {
        return _authorizer;
    }

    function setAuthorizer(IAuthorizer newAuthorizer) external {
        _authorizer = newAuthorizer;
    }
}
