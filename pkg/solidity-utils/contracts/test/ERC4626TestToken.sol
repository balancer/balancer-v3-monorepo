// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";

import { ERC20TestToken } from "./ERC20TestToken.sol";
import { FixedPoint } from "../math/FixedPoint.sol";

contract ERC4626TestToken is ERC4626, IRateProvider {
    using SafeERC20 for IERC20;
    using FixedPoint for uint256;

    uint8 private immutable _wrappedTokenDecimals;
    IERC20 private _overrideAsset;

    bool private maliciousWrapper;

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
        // The rate is calculated using the most pessimistic scenario, which is rounding down.
        return _convertToAssets(FixedPoint.ONE, Math.Rounding.Floor);
    }

    /**
     * @notice Mints underlying and/or wrapped amount to the ERC4626 token.
     * @dev If we set a rate to the ERC4626 token directly, we do not reproduce rounding issues when dividing assets
     * by total supply. The best way to mock a rate is to inflate underlying and wrapped amounts.
     * For example, let's say we have an ERC4626 token with 100 underlying and 100 total supply (or wrapped amount).
     * If we want to set the rate to 2, we need to call `inflateUnderlyingOrWrapped(100, 0)`, so that the final
     * asset balance is 200 and the final total supply is still 100 (200/100 = 2).
     * However, if we want the rate to be 0.5, we need to call `inflateUnderlyingOrWrapped(0, 100)`, so that underlying
     * balance does not change but final total supply is 200 (100/200 = 0.5).
     */
    function inflateUnderlyingOrWrapped(uint256 underlyingDelta, uint256 wrappedDelta) external {
        if (underlyingDelta > 0) {
            // Mint underlying to the address of the wrapper, increasing the token rate.
            ERC20TestToken(address(_overrideAsset)).mint(address(this), underlyingDelta);
        }
        if (wrappedDelta > 0) {
            // Mint wrapped to address 0, decreasing the token rate.
            _mint(address(0), wrappedDelta);
        }
    }

    /**
     * @notice Use inflateUnderlyingOrWrapped to inflate underlying or total supply amounts, which sets the current
     * token rate to the desired rate.
     * @dev Although this function is a shortcut to inflateUnderlyingOrWrapped, it has a limited power: it cannot
     * reproduce a rate that is not exact between assets and shares. So, if we want to test a rate that is problematic,
     * we need to use the inflateUnderlyingOrWrapped and not this one.
     */
    function mockRate(uint256 newRate) external {
        uint256 totalWrappedAmount = ERC4626TestToken(address(this)).totalSupply();
        uint256 totalUnderlyingAmount = ERC4626TestToken(address(this)).totalAssets();

        uint256 underlyingDelta;
        uint256 wrappedDelta;

        // If rate is lower than current rate, inflates the total supply. Else, inflates the underlying amount.
        if (newRate < ERC4626TestToken(address(this)).getRate()) {
            uint256 newTotalWrappedAmount = totalUnderlyingAmount.divDown(newRate);
            wrappedDelta = newTotalWrappedAmount - totalWrappedAmount;
        } else {
            uint256 newTotalUnderlyingAmount = totalWrappedAmount.mulDown(newRate);
            underlyingDelta = newTotalUnderlyingAmount - totalUnderlyingAmount;
        }

        ERC4626TestToken(address(this)).inflateUnderlyingOrWrapped(underlyingDelta, wrappedDelta);
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

    function setMaliciousWrapper(bool value) external {
        maliciousWrapper = value;
    }

    function convertToAssets(uint256 shares) public view override returns (uint256) {
        if (maliciousWrapper) {
            return _overrideAsset.balanceOf(msg.sender);
        }
        return super.convertToAssets(shares);
    }

    function deposit(uint256 assets, address receiver) public override returns (uint256) {
        if (maliciousWrapper) {
            // A malicious wrapper does nothing so it can use the approval to drain the vault.
            return 0;
        }

        return super.deposit(assets, receiver);
    }

    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
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

        _burn(owner, shares);
        SafeERC20.safeTransfer(_overrideAsset, receiver, assets);
    }
}
