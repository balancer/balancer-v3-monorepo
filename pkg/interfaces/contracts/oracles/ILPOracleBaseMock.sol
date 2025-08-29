// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

interface ILPOracleBaseMock {
    function computeFeedTokenDecimalScalingFactor(AggregatorV3Interface feed) external view returns (uint256);
}
