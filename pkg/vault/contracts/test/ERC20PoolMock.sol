// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "../ERC20BalancerPoolToken.sol";

contract ERC20PoolMock is ERC20BalancerPoolToken {
    IVault private immutable _vault;

    constructor(
        IVault vault,
        string memory name,
        string memory symbol,
        address factory,
        IERC20[] memory tokens,
        bool registerPool
    ) ERC20BalancerPoolToken(vault, name, symbol) {
        _vault = vault;

        if (registerPool) {
            vault.registerPool(factory, tokens);
        }
    }
}
