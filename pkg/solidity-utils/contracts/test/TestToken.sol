// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "../openzeppelin/ERC20.sol";

contract TestToken is ERC20 {
    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals
    ) ERC20(name, symbol) {
        _setupDecimals(decimals);
    }

    function mint(address recipient, uint256 amount) external {
        _mint(recipient, amount);
    }

    // burnWithoutAllowance was created to allow burn of token without approval. Example of use:
    //
    // MockGearboxVault.sol can't use burnFrom function (from ERC20Burnable) in unit tests, since
    // MockGearboxVault doesn't have permission to burn relayer wrapped tokens and relayer is not a Signer
    function burnWithoutAllowance(address sender, uint256 amount) external {
        _burn(sender, amount);
    }
}
