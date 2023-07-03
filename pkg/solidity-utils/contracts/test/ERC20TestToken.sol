// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ERC20TestToken is ERC20 {
    uint8 private immutable _decimals;

    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals_
    ) ERC20(name, symbol) {
        _decimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address recipient, uint256 amount) external {
        _mint(recipient, amount);
    }

    // burnWithoutAllowance was created to allow burning tokens without approval. Example of use:
    //
    // MockGearboxVault.sol can't use burnFrom function (from ERC20Burnable) in unit tests, since
    // MockGearboxVault doesn't have permission to burn relayer wrapped tokens and relayer is not a Signer
    function burnWithoutAllowance(address sender, uint256 amount) external {
        _burn(sender, amount);
    }
}
