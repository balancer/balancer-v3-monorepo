// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

interface IWeightedLPOracle {
    /**
     * @notice Gets the current weights of the tokens in the pool.
     * @return An array of weights corresponding to each token in the pool
     */
    function getWeights() external view returns (uint256[] memory);

    /**
     * @notice Gets the tokens in the pool.
     * @return An array of token addresses, sorted in token registration order
     */
    function getPoolTokens() external view returns (IERC20[] memory);
}
