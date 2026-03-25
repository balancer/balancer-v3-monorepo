// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @notice ERC20 that charges a fee (burn) on transfer/transferFrom.
 * @dev This breaks the Router/Vault assumption that an exact amount was transferred, so operations should
 * safely revert.
 */
contract ERC20FeeOnTransferToken is ERC20 {
    uint8 private immutable _decimals;
    uint256 private immutable _feeBps;

    constructor(string memory n, string memory s, uint8 d, uint256 feeBps) ERC20(n, s) {
        _decimals = d;
        _feeBps = feeBps;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function _update(address from, address to, uint256 amount) internal override {
        if (from != address(0) && to != address(0) && _feeBps != 0) {
            uint256 fee = (amount * _feeBps) / 10_000;
            uint256 sendAmount = amount - fee;
            super._update(from, to, sendAmount);
            if (fee != 0) super._update(from, address(0), fee);
            return;
        }
        super._update(from, to, amount);
    }
}
