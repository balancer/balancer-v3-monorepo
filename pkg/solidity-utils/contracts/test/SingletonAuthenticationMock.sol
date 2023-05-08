// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.7.0;

import "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import "../helpers/SingletonAuthentication.sol";

contract SingletonAuthenticationMock is SingletonAuthentication {
    constructor(IVault vault) SingletonAuthentication(vault) {
      // solhint-disable-previous-line no-empty-blocks
    }
}
