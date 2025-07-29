// SPDX-License-Identifier: GPL-3.0-or-later

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

pragma solidity ^0.8.24;

interface ITokenPairRegistry {
    /**
     * @notice Emitted when a new token pair is added to the registry.
     * @param pool The address of the pool that supports the token pair
     * @param tokenA The address of the first token in the pair
     * @param tokenB The address of the second token in the pair
     */
    event TokenPairAdded(address indexed pool, address indexed tokenA, address indexed tokenB);

    /**
     * @notice Emitted when an existing token pair is removed from the registry.
     * @param pool The address of the pool that supports the token pair
     * @param tokenA The address of the first token in the pair
     * @param tokenB The address of the second token in the pair
     */
    event TokenPairRemoved(address indexed pool, address indexed tokenA, address indexed tokenB);

    /**
     * @notice Emitted when a adding a pool or buffer for a given pair which had already been added to the registry.
     * @param pool The address of the pool or buffer that was already added
     * @param tokenA The address of the first token in the pair
     * @param tokenB The address of the second token in the pair
     */
    error PoolAlreadyAddedForPair(address pool, address tokenA, address tokenB);

    /**
     * @notice Emitted when a removing a pool or buffer for a given pair which had not been added to the registry.
     * @param pool The address of the pool or buffer being removed
     * @param tokenA The address of the first token in the pair
     * @param tokenB The address of the second token in the pair
     */
    error PoolNotAddedForPair(address pool, address tokenA, address tokenB);

    /**
     * @notice Returns the pool address for a given token pair at a specific index.
     * @dev Safe version, reverts if the index is out of bounds.
     * @param tokenA The address of the first token in the pair
     * @param tokenB The address of the second token in the pair
     * @param index The index of the pool in the list of pools for the token pair
     * @return The address of the pool at the specified index for the token pair
     */
    function getPoolAt(address tokenA, address tokenB, uint256 index) external view returns (address);

    /**
     * @notice Returns the pool address for a given token pair at a specific index.
     * @dev Unsafe version, use only when index is known to be within bounds.
     * @param tokenA The address of the first token in the pair
     * @param tokenB The address of the second token in the pair
     * @param index The index of the pool in the list of pools for the token pair
     * @return The address of the pool at the specified index for the token pair
     */
    function getPoolAtUnchecked(address tokenA, address tokenB, uint256 index) external view returns (address);

    /**
     * @notice Returns the number of pools registered for a given token pair.
     * @param tokenA The address of the first token in the pair
     * @param tokenB The address of the second token in the pair
     * @return The number of pools registered for the token pair
     */
    function getPoolCount(address tokenA, address tokenB) external view returns (uint256);

    /**
     * @notice Returns the pools registered for a given token pair.
     * @param tokenA The address of the first token in the pair
     * @param tokenB The address of the second token in the pair
     * @return An array of pool addresses registered for the token pair
     */
    function getPools(address tokenA, address tokenB) external view returns (address[] memory);

    /**
     * @notice Returns true if a pool is registered for a given token pair.
     * @param tokenA The address of the first token in the pair
     * @param tokenB The address of the second token in the pair
     * @return True if the pool is registered for the given token pair, false otherwise
     */
    function hasPool(address tokenA, address tokenB, address pool) external view returns (bool);

    /**
     * @notice Adds a pool to the registry for all token pairs it supports.
     * @dev This function is permissioned. The call will revert if the pool is already registered for the token pair.
     */
    function addPool(address pool) external;

    /**
     * @notice Adds a buffer to the registry, supporting underlying <> wrapped operations.
     * @dev This function is permissioned. The call will revert if the buffer is already registered for the token pair.
     */
    function addBuffer(IERC4626 wrappedToken) external;

    function removePool(address pool) external;

    function removeBuffer(IERC4626 wrappedToken) external;
}
