// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

/**
 * @notice Minimal Chainlink price feed that always returns 1.
 * @dev Useful for LP oracles where the rate provider already reflects the market price (e.g., XAUt).
 */
contract ConstantPriceFeed is AggregatorV3Interface {
    // solhint-disable const-name-snakecase
    string public constant override description = "Constant 1.0 Price Feed";
    uint8 public constant override decimals = 18;
    uint256 public constant override version = 1;

    // solhint-disable not-rely-on-time

    /**
     * @notice Return a constant value of 1.0 to all requests.
     * @dev Use 18 decimals, and the current timestamp.
     * @return roundId Unused / obsolete
     * @return answer Fixed value of 1.0
     * @return startedAt Started/updated values are irrelevant for a constant feed
     * @return updatedAt Just return the current timestamp for both
     * @return answeredInRound Unused / obsolete
     */
    function latestRoundData() external view override returns (uint80, int256, uint256, uint256, uint80) {
        return _fixedPrice();
    }

    // Obsolete function; return the same if called.
    function getRoundData(uint80) external view override returns (uint80, int256, uint256, uint256, uint80) {
        return _fixedPrice();
    }

    function _fixedPrice() internal view returns (uint80, int256, uint256, uint256, uint80) {
        return (0, int256(FixedPoint.ONE), block.timestamp, block.timestamp, 0);
    }
}
