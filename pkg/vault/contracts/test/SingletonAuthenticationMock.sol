// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { SingletonAuthentication } from "../SingletonAuthentication.sol";

contract SingletonAuthenticationMock is SingletonAuthentication {
    constructor(IVault vault) SingletonAuthentication(vault) {
        // solhint-disable-previous-line no-empty-blocks
    }

    function swapModifier(address pool) public onlySwapFeeManagerOrGovernance(pool) {
        // solhint-disable-previous-line no-empty-blocks
    }
}
