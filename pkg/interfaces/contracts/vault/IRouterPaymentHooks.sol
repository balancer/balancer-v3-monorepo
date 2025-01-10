// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IRouterPaymentHooks {
    function onPay(IERC20 token, uint256 amount, bytes calldata userData) external;
}
