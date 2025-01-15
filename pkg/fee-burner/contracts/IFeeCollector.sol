// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IFeeCollector {
    enum Epoch {
        SLEEP,
        COLLECT,
        EXCHANGE,
        FORWARD
    }

    struct Transfer {
        IERC20 coin;
        address to;
        // 2^256-1 for the whole balance
        uint256 amount;
    }

    function fee(Epoch epoch, uint256 timestamp) external view returns (uint256);

    function target() external view returns (IERC20);

    function owner() external view returns (address);

    function emergency_owner() external view returns (address);

    function epoch_time_frame(Epoch epoch, uint256 timestamp) external view returns (uint256, uint256);

    function can_exchange(IERC20[] memory coins) external view returns (bool);

    function transfer(Transfer[] memory transfers) external;
}
