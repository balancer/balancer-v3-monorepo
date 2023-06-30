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

    // Used for testing the ReentrancyGuard
    function reentrantRegisterPool(address factory, IERC20[] memory tokens) external nonReentrant {
        this.registerPool(factory, tokens);
    }

    // Used for testing pool registration, which is ordinarily done in the constructor of the pool.
    // The Mock pool has an argument for whether or not to register on deployment. To call register pool
    // separately, deploy it with the registration flag false, then call this function.
    function manualRegisterPool(address factory, IERC20[] memory tokens) external whenNotPaused {
        _registerPool(factory, tokens);
    }
}
