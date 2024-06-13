// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

/**
 * @notice Return the minimum/maximum swap fee percentages for a pool.
 * @dev The Vault does not enforce bounds on swap fee percentages; `IBasePool` implements this interface to ensure
 * that new pool developers think about and set these bounds according to their specific pool type.
 *
 * A minimum swap fee might be necessary to ensure mathematical soundness (e.g., Weighted Pools, which use the power
 * function in the invariant). A maximum swap fee is general protection for users. With no limits at the Vault level,
 * a pool could specify a 100% swap fee, effectively disabling trading. Though there are some use cases, such as
 * LVR/MEV strategies, where a 100% fee makes sense.
 */
interface ISwapFeePercentageBounds {
    /// @return minimumSwapFeePercentage The minimum swap fee percentage for a pool
    function getMinimumSwapFeePercentage() external view returns (uint256);

    /// @return maximumSwapFeePercentage The maximum swap fee percentage for a pool
    function getMaximumSwapFeePercentage() external view returns (uint256);
}
