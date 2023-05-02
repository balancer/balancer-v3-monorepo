// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

import "../openzeppelin/ERC20.sol";

/**
 * @dev ERC20 with a modified `approve` function, which always returns false.
 */
contract ERC20FalseApprovalMock is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        _approve(msg.sender, spender, amount);
        return false;
    }
}
