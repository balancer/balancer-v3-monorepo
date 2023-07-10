// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";

import { Asset, AssetHelpers } from "../helpers/AssetHelpers.sol";

contract AssetHelpersMock {
    using AssetHelpers for Asset;
    using AssetHelpers for Asset[];

    function isETH(Asset asset) external pure returns (bool) {
        return asset.isETH();
    }

    function toIERC20(Asset asset, IWETH weth) external pure returns (IERC20) {
        return asset.toIERC20(weth);
    }

    function toIERC20(Asset[] memory assets, IWETH weth) external pure returns (IERC20[] memory) {
        return assets.toIERC20(weth);
    }
}
