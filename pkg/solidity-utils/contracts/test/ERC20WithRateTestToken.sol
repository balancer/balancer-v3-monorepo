// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";

import "./ERC20TestToken.sol";

contract ERC20WithRateTestToken is IRateProvider, ERC20TestToken {
    uint256 private _rate;

    constructor(string memory name, string memory symbol, uint8 decimals_) ERC20TestToken(name, symbol, decimals_) {
        _rate = 1e18;
    }

    function setRate(uint256 newRate) external {
        _rate = newRate;
    }

    function getRate() external view override returns (uint256) {
        return _rate;
    }
}
