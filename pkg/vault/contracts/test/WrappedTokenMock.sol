// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

contract WrappedTokenMock is IERC4626 {
    using FixedPoint for uint256;

    address private immutable _baseToken;
    uint256 private immutable _decimalDiff;

    string private _name;
    string private _symbol;
    uint8 private _decimals;
    uint256 private _totalAssets;
    uint256 private _totalSupply;

    constructor(address underlyingToken, string memory tokenName, string memory tokenSymbol, uint8 tokenDecimals) {
        _baseToken = underlyingToken;

        _name = tokenName;
        _symbol = tokenSymbol;
        _decimals = tokenDecimals;

        _decimalDiff = 10 ** (18 + tokenDecimals - IERC20Metadata(underlyingToken).decimals());
    }

    function setTotalSupply(uint256 newTotalSupply) external {
        _totalSupply = newTotalSupply;
    }

    function setTotalAssets(uint256 newTotalAssets) external {
        _totalAssets = newTotalAssets;
    }

    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view override returns (uint256) {}

    function transfer(address to, uint256 value) external override returns (bool) {}

    function allowance(address owner, address spender) external view override returns (uint256) {}

    function approve(address spender, uint256 value) external override returns (bool) {}

    function transferFrom(address from, address to, uint256 value) external override returns (bool) {}

    function name() external view override returns (string memory) {
        return _name;
    }

    function symbol() external view override returns (string memory) {
        return _symbol;
    }

    function decimals() external view override returns (uint8) {
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

    function maxDeposit(address receiver) external view override returns (uint256 maxAssets) {}

    function previewDeposit(uint256 assets) external view override returns (uint256 shares) {}

    function deposit(uint256 assets, address receiver) external override returns (uint256 shares) {}

    function maxMint(address receiver) external view override returns (uint256 maxShares) {}

    function previewMint(uint256 shares) external view override returns (uint256 assets) {}

    function mint(uint256 shares, address receiver) external override returns (uint256 assets) {}

    function maxWithdraw(address owner) external view override returns (uint256 maxAssets) {}

    function previewWithdraw(uint256 assets) external view override returns (uint256 shares) {}

    function withdraw(uint256 assets, address receiver, address owner) external override returns (uint256 shares) {}

    function maxRedeem(address owner) external view override returns (uint256 maxShares) {}

    function previewRedeem(uint256 shares) external view override returns (uint256 assets) {}

    function redeem(uint256 shares, address receiver, address owner) external override returns (uint256 assets) {}
}
