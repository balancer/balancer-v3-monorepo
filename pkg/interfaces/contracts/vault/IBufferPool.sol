// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

/// @notice Interface for an ERC4626BufferPool
interface IBufferPool {
    /// @notice Explicitly rebalance a Buffer Pool, outside of a swap operation. This is a permissioned function.
    function rebalance() external;

    /// @notice Return the index of the wrapped token (tokens must be sorted).
    function getWrappedTokenIndex() external view returns (uint256);

    /// @notice Return the index of the base token (tokens must be sorted).
    function getBaseTokenIndex() external view returns (uint256);
}
