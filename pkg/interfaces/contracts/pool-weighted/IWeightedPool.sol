// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

/// @notice Interface for a Weighted Pool
interface IWeightedPool {
    /// @dev Indicates that one of the pool tokens' weight is below the minimum allowed.
    error MinWeight();

    /// @dev Indicates that the sum of the pool tokens' weights is not FP 1.
    error NormalizedWeightInvariant();
}
