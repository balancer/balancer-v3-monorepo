// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.20;

import "../Router.sol";

contract RouterMock is Router {
    constructor(IVault vault, IWETH weth) Router(vault, weth) {}

    function getSingleInputArrayAndTokenIndex(
        address pool,
        IERC20 token,
        uint256 amountGiven
    ) external view returns (uint256[] memory amountsGiven, uint256 tokenIndex) {
        return _getSingleInputArrayAndTokenIndex(pool, token, amountGiven);
    }
}
