// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

import "../openzeppelin/ERC20.sol";

contract ERC20Mock is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address recipient, uint256 amount) external {
        _mint(recipient, amount);
    }

    function burn(address sender, uint256 amount) external {
        _burn(sender, amount);
    }
}
