// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "../Vault.sol";

contract VaultMock is Vault {
    constructor(
        IWETH weth,
        uint256 pauseWindowDuration,
        uint256 bufferPeriodDuration
    ) Vault(weth, pauseWindowDuration, bufferPeriodDuration) {
        // solhint-disable-previous-line no-empty-blocks
    }

    function isETH(IAsset asset) external pure returns (bool) {
        return _isETH(asset);
    }

    function translateToIERC20(IAsset asset) external view returns (IERC20) {
        return _translateToIERC20(asset);
    }

    function translateToIERC20(IAsset[] memory assets) external view returns (IERC20[] memory) {
        return _translateToIERC20(assets);
    }
}
