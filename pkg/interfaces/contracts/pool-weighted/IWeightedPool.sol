// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IBasePool } from "../vault/IBasePool.sol";

struct WeightedPoolImmutableData {
    IERC20[] tokens;
    uint256[] decimalScalingFactors;
    uint256[] normalizedWeights;
}

struct WeightedPoolDynamicData {
    uint256[] liveBalances;
    uint256[] tokenRates;
    uint256 staticSwapFeePercentage;
    uint256 totalSupply;
    uint256 bptRate;
}

/// @notice Full Weighted pool interface.
interface IWeightedPool is IBasePool {
    /**
     * @dev Get the normalized weights.
     * @return An array of normalized weights, sorted in token registration order
     */
    function getNormalizedWeights() external view returns (uint256[] memory);

     /// @notice Get relevant dynamic pool data required for swap / add / remove calculations.
    function getWeightedPoolDynamicData() external view returns (WeightedPoolDynamicData memory data);

     /// @notice Get relevant immutable pool data required for swap / add / remove calculations.
    function getWeightedPoolImmutableData() external view returns (WeightedPoolImmutableData memory data);
}
