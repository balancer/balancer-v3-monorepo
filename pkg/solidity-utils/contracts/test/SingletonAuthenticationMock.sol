// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

import "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import "../helpers/SingletonAuthentication.sol";

contract SingletonAuthenticationMock is SingletonAuthentication {
    constructor(IVault vault) SingletonAuthentication(vault) {
      // solhint-disable-previous-line no-empty-blocks
    }

    function canPerform(bytes32 actionId, address account) external view returns (bool) {
        return _canPerform(actionId, account, address(this));
    }
}
