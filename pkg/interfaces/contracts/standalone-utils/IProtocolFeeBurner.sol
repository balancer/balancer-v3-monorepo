// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IProtocolFeeBurner {
    function burn(IERC20 tokenIn, uint256 tokenInAmount, IERC20 tokenOut, address recipient) external returns(uint256 tokenOutAmount);
}
