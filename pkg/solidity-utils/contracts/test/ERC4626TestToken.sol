// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { ERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";

import { FixedPoint } from "../math/FixedPoint.sol";

contract ERC4626TestToken is ERC4626, IRateProvider {
    using Math for uint256;

    uint8 private immutable _wrappedTokenDecimals;

    constructor(
        IERC20 baseToken,
        string memory tokenName,
        string memory tokenSymbol,
        uint8 tokenDecimals
    ) ERC4626(baseToken) ERC20(tokenName, tokenSymbol) {
        _wrappedTokenDecimals = tokenDecimals;
    }

    function decimals() public view virtual override returns (uint8) {
        return _wrappedTokenDecimals;
    }

    function getRate() external view returns (uint256) {
        return _convertToAssets(FixedPoint.ONE, Math.Rounding.Floor);
    }

    function mint(uint256 shares, address receiver) public virtual override returns (uint256) {
        _mint(receiver, shares);

        return shares;
    }
}
