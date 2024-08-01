// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";

import { FixedPoint } from "../math/FixedPoint.sol";

contract ERC4626TestToken is ERC4626, IRateProvider {
    using SafeERC20 for IERC20;

    uint8 private immutable _wrappedTokenDecimals;
    IERC20 private _overrideAsset;

    uint256 private _assetsToConsume;
    uint256 private _sharesToConsume;
    uint256 private _assetsToReturn;
    uint256 private _sharesToReturn;

    constructor(
        IERC20 underlyingToken,
        string memory tokenName,
        string memory tokenSymbol,
        uint8 tokenDecimals
    ) ERC4626(underlyingToken) ERC20(tokenName, tokenSymbol) {
        _wrappedTokenDecimals = tokenDecimals;
        _overrideAsset = underlyingToken;
    }

    function decimals() public view override returns (uint8) {
        return _wrappedTokenDecimals;
    }

    function getRate() external view returns (uint256) {
        return _convertToAssets(FixedPoint.ONE, Math.Rounding.Ceil);
    }

    /*****************************************************************
                         Test malicious ERC4626
    *****************************************************************/

    function asset() public view override returns (address) {
        return address(_overrideAsset);
    }

    function totalAssets() public view override returns (uint256) {
        return _overrideAsset.balanceOf(address(this));
    }

    function setAsset(IERC20 newBaseToken) external {
        _overrideAsset = newBaseToken;
    }

    function setAssetsToConsume(uint256 assetsToConsume) external {
        _assetsToConsume = assetsToConsume;
    }

    function setSharesToConsume(uint256 sharesToConsume) external {
        _sharesToConsume = sharesToConsume;
    }

    function setAssetsToReturn(uint256 assetsToReturn) external {
        _assetsToReturn = assetsToReturn;
    }

    function setSharesToReturn(uint256 sharesToReturn) external {
        _sharesToReturn = sharesToReturn;
    }

    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        if (_assetsToConsume > 0) {
            assets = _assetsToConsume;
        }
        if (_sharesToReturn > 0) {
            shares = _sharesToReturn;
        }

        _overrideAsset.safeTransferFrom(caller, address(this), assets);
        _mint(receiver, shares);
    }

    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal override {
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }

        if (_sharesToConsume > 0) {
            shares = _sharesToConsume;
        }
        if (_assetsToReturn > 0) {
            assets = _assetsToReturn;
        }

        _burn(owner, shares);
        SafeERC20.safeTransfer(_overrideAsset, receiver, assets);
    }
}
