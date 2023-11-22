// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";

import "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

contract RateProviderMock is IRateProvider {
    uint256 internal _rate;
    IERC20 internal _underlyingToken;

    constructor() {
        _rate = FixedPoint.ONE;
    }

    function setUnderlyingToken(IERC20 token) external {
        _underlyingToken = token;
    }

    function getRate() external view override returns (uint256) {
        return _rate;
    }

    function mockRate(uint256 newRate) external {
        _rate = newRate;
    }

    function getUnderlyingToken() external view returns (IERC20) {
        return _underlyingToken;
    }
}
