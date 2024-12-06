// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

/**
 * @notice Return the minimum/maximum swap fee percentages for a pool.
 * @dev The Vault does not enforce bounds on swap fee percentages; `IBasePool` implements this interface to ensure
 * that new pool developers think about and set these bounds according to their specific pool type.
 *
 * A minimum swap fee might be necessary to ensure mathematical soundness (e.g., Weighted Pools, which use the power
 * function in the invariant). A maximum swap fee is general protection for users. With no limits at the Vault level,
 * a pool could specify a near 100% swap fee, effectively disabling trading. Though there are some use cases, such as
 * LVR/MEV strategies, where a very high fee makes sense.
 *
 * Note that the Vault does ensure that dynamic and aggregate fees are less than 100% to prevent attempting to allocate
 * more fees than were collected by the operation. The true `MAX_FEE_PERCENTAGE` is defined in VaultTypes.sol, and is
 * the highest value below 100% that satisfies the precision requirements.
 */
interface ISwapFeePercentageBounds {
    /// @return minimumSwapFeePercentage The minimum swap fee percentage for a pool
    function getMinimumSwapFeePercentage() external view returns (uint256 minimumSwapFeePercentage);

    /// @return maximumSwapFeePercentage The maximum swap fee percentage for a pool
    function getMaximumSwapFeePercentage() external view returns (uint256 maximumSwapFeePercentage);
}
