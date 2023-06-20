// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "../Vault.sol";
import "../lib/AssetHelpersLib.sol";

contract VaultMock is Vault {
    constructor(
        IWETH weth,
        uint256 pauseWindowDuration,
        uint256 bufferPeriodDuration
    ) Vault(weth, pauseWindowDuration, bufferPeriodDuration) {
        // solhint-disable-previous-line no-empty-blocks
    }

    function isETH(IAsset asset) external pure returns (bool) {
        return AssetHelpersLib.isETH(asset);
    }

    function translateToIERC20(IAsset asset) external view returns (IERC20) {
        return AssetHelpersLib.translateToIERC20(asset, WETH());
    }

    function translateToIERC20(IAsset[] memory assets) external view returns (IERC20[] memory) {
        return AssetHelpersLib.translateToIERC20(assets, WETH());
    }
}
