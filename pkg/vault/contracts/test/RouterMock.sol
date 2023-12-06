// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "../Router.sol";

contract RouterMock is Router {
    constructor(IVault vault, IWETH weth) Router(vault, weth) {}

    function getSingleInputArray(
        address pool,
        uint256 tokenIndex,
        uint256 amountGiven
    ) external view returns (uint256[] memory amountsGiven) {
        return _getSingleInputArray(pool, tokenIndex, amountGiven);
    }
}
