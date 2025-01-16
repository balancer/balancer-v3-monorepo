// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IProtocolFeeSweeper {
    /**
     * @notice Withdraw, convert, and forward protocol fees for a given pool.
     * @dev This will withdraw all fee tokens to this contract, and attempt to convert and forward them.
     * @param pool The pool from which we're withdrawing fees
     */
    function sweepProtocolFees(address pool) external;

    /**
     * @notice Withdraw, convert, and forward protocol fees for a given pool and token.
     * @dev This will withdraw any fees collected on that pool and token, and attempt to convert and forward them.
     * @param pool The pool from which we're withdrawing fees
     * @param token The fee token
     */
    function sweepProtocolFeesForToken(address pool, IERC20 token) external;
}
