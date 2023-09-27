// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { ERC20PoolToken } from "./ERC20PoolToken.sol";

contract BasePoolToken is ERC20PoolToken {
    constructor(IVault vault_, string memory name_, string memory symbol_) ERC20PoolToken(vault_, name_, symbol_) {
        // solhint-disable-previous-line no-empty-blocks
    }
}
