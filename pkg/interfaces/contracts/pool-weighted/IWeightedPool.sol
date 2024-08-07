// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IBasePool } from "../vault/IBasePool.sol";

/**
 * @notice Weighted Pool data that cannot change after deployment.
 * @param tokens Pool tokens, sorted in pool registration order
 * @param decimalScalingFactors Conversion factor used to adjust for token decimals for uniform precision in
 * calculations. FP(1) for 18-decimal tokens
 * @param
 */
struct WeightedPoolImmutableData {
    IERC20[] tokens;
    uint256[] decimalScalingFactors;
    uint256[] normalizedWeights;
}

/**
 * @notice Snapshot of current Weighted Pool data that can change.
 * @param balancesLiveScaled18 Token balances after paying yield fees, applying decimal scaling and rates
 * @param tokenRates 18-decimal FP values for rate tokens (e.g., yield-bearing), or FP(1) for standard tokens
 * @param staticSwapFeePercentage 18-decimal FP value of the static swap fee percentage
 * @param totalSupply The current total supply of the pool tokens (BPT)
 * @param bptRate The current rate of a pool token (BPT) = invariant / totalSupply
 */
struct WeightedPoolDynamicData {
    uint256[] balancesLiveScaled18;
    uint256[] tokenRates;
    uint256 staticSwapFeePercentage;
    uint256 totalSupply;
    uint256 bptRate;
}

/// @notice Full Weighted pool interface.
interface IWeightedPool is IBasePool {
    /**
     * @notice Get the normalized weights.
     * @return The normalized weights, sorted in token registration order
     */
    function getNormalizedWeights() external view returns (uint256[] memory);

    /**
     * @notice Get relevant dynamic pool data required for swap/add/remove calculations.
     * @return data A struct containing all dynamic weighted pool parameters
     */
    function getWeightedPoolDynamicData() external view returns (WeightedPoolDynamicData memory data);

    /**
     * @notice Get relevant immutable pool data required for swap/add/remove calculations.
     * @return data A struct containing all immutable weighted pool parameters
     */
    function getWeightedPoolImmutableData() external view returns (WeightedPoolImmutableData memory data);
}
