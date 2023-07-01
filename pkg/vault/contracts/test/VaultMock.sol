// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "../lib/AssetHelpersLib.sol";
import "../Vault.sol";

contract VaultMock is Vault {
    constructor(
        IWETH weth,
        uint256 pauseWindowDuration,
        uint256 bufferPeriodDuration
    ) Vault(weth, pauseWindowDuration, bufferPeriodDuration) {
        // solhint-disable-previous-line no-empty-blocks      
    }

    function mint(address poolToken, address to, uint256 amount) external {
        _mint(poolToken, to, amount);
    }

    function burn(address poolToken, address from, uint256 amount) external {
        _burn(poolToken, from, amount);
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

    function pause() external {
        _pause();
    }

    function reentrantRegisterPool(address factory, IERC20[] memory tokens) external nonReentrant {
        this.registerPool(factory, tokens);
    }
}
