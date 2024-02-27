// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

/// @notice Interface for an ERC4626BufferPool
interface IBufferPool {
    /// @notice Explicitly rebalance a Buffer Pool, outside of a swap operation. This is a permissioned function.
    function rebalance() external;
}
