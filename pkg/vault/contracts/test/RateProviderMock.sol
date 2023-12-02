// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";

import "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

contract RateProviderMock is IRateProvider {
    uint256 internal _rate;
    IERC20 internal _underlyingToken;
    bool internal _isWrappedToken;
    bool internal _isYieldExemptToken;

    constructor() {
        _rate = FixedPoint.ONE;
    }

    function setUnderlyingToken(IERC20 token) external {
        _underlyingToken = token;
    }

    /// @inheritdoc IRateProvider
    function getRate() external view override returns (uint256) {
        return _rate;
    }

    function mockRate(uint256 newRate) external {
        _rate = newRate;
    }

    /// @inheritdoc IRateProvider
    function getUnderlyingToken() external view returns (IERC20) {
        return _underlyingToken;
    }

    function setWrappedTokenFlag(bool isWrapped) external {
        _isWrappedToken = isWrapped;
    }

    /// @inheritdoc IRateProvider
    function isWrappedToken() external view returns (bool) {
        return _isWrappedToken;
    }

    function setYieldExemptFlag(bool isYieldExempt) external {
        _isYieldExemptToken = isYieldExempt;
    }

    /// @inheritdoc IRateProvider
    function isExemptFromYieldProtocolFee() external view returns (bool) {
        return _isYieldExemptToken;
    }
}
