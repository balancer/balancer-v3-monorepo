// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IProtocolFeeBurner {
    function burn(
        IERC20 feeToken,
        uint256 feeTokenAmount,
        IERC20 targetToken,
        address recipient
    ) external;
}
