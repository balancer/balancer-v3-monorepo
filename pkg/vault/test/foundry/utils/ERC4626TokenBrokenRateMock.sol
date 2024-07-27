// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { ERC4626TokenMock } from "./ERC4626TokenMock.sol";

contract ERC4626TokenBrokenRateMock is ERC4626TokenMock {
    constructor(
        string memory tokenName,
        string memory tokenSymbol,
        uint256 initialAssets,
        uint256 initialShares,
        IERC20 underlyingToken
    ) ERC4626TokenMock(tokenName, tokenSymbol, initialAssets, initialShares, underlyingToken) {}

    function _convertToShares(uint256 assets) internal view override returns (uint256) {
        uint256 sharesToAdd = (10 * assets) / 100;
        uint256 correctShares = (assets * _shares) / (_assets);
        // Non-linear formula, adds 10% of assets to final result
        return sharesToAdd + correctShares;
    }

    function _convertToAssets(uint256 shares) internal view override returns (uint256 assets) {
        uint256 assetsToAdd = (10 * shares) / 100;
        uint256 correctAssets = (shares * _assets) / _shares;
        // Non-linear formula, adds 10% of assets to final result
        return assetsToAdd + correctAssets;
    }
}
