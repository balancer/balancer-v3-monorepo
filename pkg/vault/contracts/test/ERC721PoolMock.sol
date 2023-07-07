// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "../ERC721BalancerPoolToken.sol";

contract ERC721PoolMock is ERC721BalancerPoolToken {
    IVault private immutable _vault;

    constructor(
        IVault vault,
        address factory,
        IERC20[] memory tokens,
        string memory name,
        string memory symbol,
        bool registerPool
    ) ERC721BalancerPoolToken(vault, name, symbol) {
        _vault = vault;

        if (registerPool) {
            vault.registerPool(factory, tokens);
        }
    }
}
