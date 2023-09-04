// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

/// @notice Interface for a Weighted Pool
interface IWeightedPool {
    /**
     * @dev
     */
    error MinWeight();

    /**
     * @dev
     */
    error NormalizedWeightInvariant();

    /**
     * @dev
     */
    error InvalidToken();
}
