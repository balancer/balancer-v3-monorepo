// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

import "../openzeppelin/ERC20.sol";

/**
 * @dev ERC20 with a modified approve, transfer and transferFrom functions, which revert according to a preset.
 */
contract BreakableERC20Mock is ERC20 {
    bool public isBroken;

    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function setIsBroken(bool _isBroken) external {
        isBroken = _isBroken;
    }

    function mint(address recipient, uint256 amount) external {
        _mint(recipient, amount);
    }

    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        require(!isBroken, 'BROKEN_TOKEN');
        return super.approve(spender, amount);
    }

    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        require(!isBroken, 'BROKEN_TOKEN');
        return super.transfer(recipient, amount);
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {
        require(!isBroken, 'BROKEN_TOKEN');
        return super.transferFrom(sender, recipient, amount);
    }
}
