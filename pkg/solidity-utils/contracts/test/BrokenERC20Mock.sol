// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

import "../openzeppelin/ERC20.sol";

/**
 * @dev ERC20 with a modified `approve` function, which always reverts.
 */
contract BrokenERC20Mock is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function approve(address, uint256) public virtual override returns (bool) {
        revert('BROKEN_TOKEN');
    }
}
