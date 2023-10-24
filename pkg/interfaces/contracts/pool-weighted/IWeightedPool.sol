// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

interface IWeightedPool {
    /// @dev Indicates that one of the pool token weights is below the minimum allowed.
    error MinWeight();

    /// @dev Indicates that the sum of the pool token weights is not FP 1.
    error NormalizedWeightInvariant();
}
