// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

contract ERC4626TokenMock is IERC4626, ERC20, IRateProvider {
    using SafeERC20 for IERC20;

    uint256 internal _assets;
    uint256 internal _shares;
    IERC20 internal _baseToken;

    constructor(
        string memory tokenName,
        string memory tokenSymbol,
        uint256 initialAssets,
        uint256 initialShares,
        IERC20 underlyingToken
    ) ERC20(tokenName, tokenSymbol) {
        _assets = initialAssets;
        _shares = initialShares;
        _baseToken = underlyingToken;
    }

    error NotImplemented();

    function asset() external view override returns (address) {
        return address(_baseToken);
    }

    function totalAssets() external view override returns (uint256) {
        return _assets;
    }

    function convertToShares(uint256 assets) external view override returns (uint256) {
        return _convertToShares(assets);
    }

    function convertToAssets(uint256 shares) external view override returns (uint256) {
        return _convertToAssets(shares);
    }

    function maxDeposit(address) external pure override returns (uint256) {
        revert NotImplemented();
    }

    function previewDeposit(uint256 assets) external view override returns (uint256) {
        return _convertToShares(assets);
    }

    function deposit(uint256 assets, address receiver) external override returns (uint256) {
        uint256 sharesToReturn = _convertToShares(assets);

        // Effects
        _assets += assets;
        _shares += sharesToReturn;

        // Interactions
        _baseToken.safeTransferFrom(msg.sender, address(this), assets);
        _mint(receiver, sharesToReturn);

        return sharesToReturn;
    }

    function maxMint(address) external pure override returns (uint256) {
        revert NotImplemented();
    }

    function previewMint(uint256 shares) external view override returns (uint256) {
        return _convertToAssets(shares);
    }

    function mint(uint256 shares, address receiver) external override returns (uint256) {
        uint256 assetsToDeposit = _convertToAssets(shares);

        // Effects
        _assets += assetsToDeposit;
        _shares += shares;

        // Interactions
        _baseToken.safeTransferFrom(msg.sender, address(this), assetsToDeposit);
        _mint(receiver, shares);

        return assetsToDeposit;
    }

    function maxWithdraw(address) external pure override returns (uint256) {
        revert NotImplemented();
    }

    function previewWithdraw(uint256 assets) external view override returns (uint256) {
        return _convertToShares(assets);
    }

    function withdraw(uint256 assets, address receiver, address owner) external override returns (uint256) {
        uint256 sharesToBurn = _convertToShares(assets);

        // Effects
        _assets -= assets;
        _shares -= sharesToBurn;

        // Interactions
        _burn(owner, sharesToBurn);
        _baseToken.safeTransfer(receiver, assets);

        return sharesToBurn;
    }

    function maxRedeem(address) external pure override returns (uint256) {
        revert NotImplemented();
    }

    function previewRedeem(uint256 shares) external view override returns (uint256) {
        return _convertToAssets(shares);
    }

    function redeem(uint256 shares, address receiver, address owner) external override returns (uint256) {
        uint256 assetsToReturn = _convertToAssets(shares);

        // Effects
        _assets -= assetsToReturn;
        _shares -= shares;

        // Interactions
        _burn(owner, shares);
        _baseToken.safeTransfer(receiver, assetsToReturn);

        return assetsToReturn;
    }

    function _convertToShares(uint256 assets) internal view virtual returns (uint256) {
        return (assets * _shares) / _assets;
    }

    function _convertToAssets(uint256 shares) internal view virtual returns (uint256 assets) {
        return (shares * _assets) / _shares;
    }

    function getRate() external view returns (uint256) {
        return _convertToAssets(FixedPoint.ONE);
    }
}
