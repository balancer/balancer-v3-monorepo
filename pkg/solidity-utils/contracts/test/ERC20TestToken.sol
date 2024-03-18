// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ERC20TestToken is ERC20 {
    uint8 private immutable _decimals;

    constructor(string memory name, string memory symbol, uint8 decimals_) ERC20(name, symbol) {
        _decimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address recipient, uint256 amount) external {
        _mint(recipient, amount);
    }

    function burn(address sender, uint256 amount) external {
        _burn(sender, amount);
    }
}
