// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IERC20MultiToken {
    /// @dev The total supply of a pool token can't be lower than the absolute minimum.
    error TotalSupplyTooLow(uint256 amount, uint256 limit);
}
