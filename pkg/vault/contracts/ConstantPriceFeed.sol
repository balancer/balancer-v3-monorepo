// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/// @notice Minimal Chainlink Aggregator that always returns 1.0
contract ConstantPriceFeed is AggregatorV3Interface {
    string public constant override description = "Constant 1.0 Price Feed";
    uint8 public constant override decimals = 8; // 1.00000000
    uint256 public constant override version = 1;

    error UnsupportedOperation();

    /**
     * @notice Return a constant value of 1.0 to all requests.
     * @dev Use 8 decimals (a common value), and the current timestamp.
     * @return roundId Unused / obsolete
     * @return answer Fixed value of 1.0
     * @return startedAt Started/updated values are irrelevant for a constant feed
     * @return updatedAt Just return the current timestamp for both
     * @return answeredInRound Unused / obsolete
     */
    function latestRoundData()
        external
        view
        override
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return (0, 1e8, block.timestamp, block.timestamp, 0);
    }

    function getRoundData(uint80)
        external
        pure
        override
        returns (uint80, int256, uint256, uint256, uint80)
    {
        revert UnsupportedOperation();
    }
}
