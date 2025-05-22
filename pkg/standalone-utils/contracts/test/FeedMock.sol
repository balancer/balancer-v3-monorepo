// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract FeedMock is AggregatorV3Interface {
    uint256 internal _decimals;
    uint256 internal _lastAnswer;
    uint256 internal _lastUpdatedAt;

    constructor(uint256 decimals_) {
        _decimals = decimals_;
    }

    function setDecimals(uint8 decimals_) external {
        _decimals = decimals_;
    }

    function setLastRoundData(uint256 lastAnswer, uint256 lastUpdatedAt) external {
        _lastAnswer = lastAnswer;
        _lastUpdatedAt = lastUpdatedAt;
    }

    function decimals() external view returns (uint8) {
        return uint8(_decimals);
    }

    function description() external pure returns (string memory) {
        return "Mock Chainlink Feed";
    }

    function version() external pure returns (uint256) {
        return 0;
    }

    function getRoundData(
        uint80
    )
        external
        pure
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (0, 0, 0, 0, 0);
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (0, int256(_lastAnswer), 0, _lastUpdatedAt, 0);
    }
}
