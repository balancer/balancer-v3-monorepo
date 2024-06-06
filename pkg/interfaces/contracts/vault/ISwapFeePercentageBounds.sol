// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

/**
 * @notice Return the minimum/maximum swap fee percentages for a pool.
 * @dev The Vault does not enforce bounds on swap fee percentages; it is up to the pools whether they want to
 * enforce minimum or maximum swap fee percentages, by implementing this interface. The Vault will use the ERC-165
 * standard to determine whether a given pool supports limits. If so, pools will need to implement both functions.
 */
interface ISwapFeePercentageBounds {
    /// @return minimumSwapFeePercentage The minimum swap fee percentage for a pool
    function getMinimumSwapFeePercentage() external view returns (uint256);

    /// @return maximumSwapFeePercentage The maximum swap fee percentage for a pool
    function getMaximumSwapFeePercentage() external view returns (uint256);
}
