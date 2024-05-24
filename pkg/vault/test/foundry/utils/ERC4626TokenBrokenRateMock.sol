// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { ERC4626TokenMock } from "./ERC4626TokenMock.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

contract ERC4626TokenBrokenRateMock is ERC4626TokenMock {
    using FixedPoint for uint256;
    using SafeERC20 for IERC20;

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
