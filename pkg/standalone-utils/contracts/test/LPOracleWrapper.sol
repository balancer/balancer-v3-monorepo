// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract LPOracleWrapper {
    address private oracle;
    uint256 public dummy; // dummy state variable

    constructor(address _oracle) {
        oracle = _oracle;
    }

    function callLatestRoundData() external returns (uint80, int256, uint256, uint256, uint80) {
        dummy = block.timestamp; // write to state to justify non-view (solhint-disable does not work)
        return AggregatorV3Interface(oracle).latestRoundData();
    }
}
