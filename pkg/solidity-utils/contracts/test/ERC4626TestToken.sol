// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";

import { FixedPoint } from "../math/FixedPoint.sol";

contract ERC4626TestToken is IERC4626, ERC20, IRateProvider {
    using FixedPoint for uint256;

    address private immutable _baseToken;
    uint256 private immutable _rateScalingFactor;

    uint8 private _decimals;
    uint256 private _totalAssets;
    uint256 private _totalSupply;

    constructor(
        address baseToken,
        string memory tokenName,
        string memory tokenSymbol,
        uint8 tokenDecimals
    ) ERC20(tokenName, tokenSymbol) {
        _baseToken = baseToken;
        _decimals = tokenDecimals;

        _rateScalingFactor = 10 ** (18 + tokenDecimals - IERC20Metadata(baseToken).decimals());
    }

    function setTotalSupply(uint256 newTotalSupply) external {
        _totalSupply = newTotalSupply;
    }

    function setTotalAssets(uint256 newTotalAssets) external {
        _totalAssets = newTotalAssets;
    }

    function totalSupply() public view override(IERC20, ERC20) returns (uint256) {
        return _totalSupply;
    }

    function decimals() public view override(ERC20, IERC20Metadata) returns (uint8) {
        return _decimals;
    }

    function asset() external view override returns (address assetTokenAddress) {
        return _baseToken;
    }

    function totalAssets() external view override returns (uint256 totalManagedAssets) {
        return _totalAssets;
    }

    function convertToShares(uint256 assets) external view override returns (uint256 shares) {
        return (assets == 0 || _totalSupply == 0) ? assets : assets.mulDown(_totalSupply).divDown(_totalAssets);
    }

    function convertToAssets(uint256 shares) external view override returns (uint256 assets) {
        return (_totalSupply == 0) ? shares : shares.mulDown(_totalAssets).divDown(_totalSupply);
    }

    function getRate() external view returns (uint256) {
        return (_totalSupply == 0) ? FixedPoint.ONE : _rateScalingFactor.mulDown(_totalAssets).divDown(_totalSupply);
    }

    function maxDeposit(address receiver) external view override returns (uint256 maxAssets) {}

    function previewDeposit(uint256 assets) external view override returns (uint256 shares) {}

    function deposit(uint256 assets, address receiver) external override returns (uint256 shares) {}

    function maxMint(address receiver) external view override returns (uint256 maxShares) {}

    function previewMint(uint256 shares) external view override returns (uint256 assets) {}

    function mint(uint256 shares, address receiver) external override returns (uint256 assets) {
        _mint(receiver, shares);
        assets = shares;
    }

    function maxWithdraw(address owner) external view override returns (uint256 maxAssets) {}

    function previewWithdraw(uint256 assets) external view override returns (uint256 shares) {}

    function withdraw(uint256 assets, address receiver, address owner) external override returns (uint256 shares) {}

    function maxRedeem(address owner) external view override returns (uint256 maxShares) {}

    function previewRedeem(uint256 shares) external view override returns (uint256 assets) {}

    function redeem(uint256 shares, address receiver, address owner) external override returns (uint256 assets) {}
}
