// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { ERC20FacadeToken } from "./ERC20FacadeToken.sol";

contract BasePoolToken is ERC20FacadeToken {
    constructor(
        IVault vault_,
        string memory name_,
        string memory symbol_
    ) ERC20FacadeToken(vault_, name_, symbol_) {}
}
