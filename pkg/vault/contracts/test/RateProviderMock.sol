// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

contract RateProviderMock is IRateProvider {
    uint256 internal _rate;

    constructor() {
        _rate = FixedPoint.ONE;
    }

    /// @inheritdoc IRateProvider
    function getRate() external view override returns (uint256) {
        return _rate;
    }

    function mockRate(uint256 newRate) external {
        _rate = newRate;
    }
}
