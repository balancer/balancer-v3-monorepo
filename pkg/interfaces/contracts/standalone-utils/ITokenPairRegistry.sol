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
     * @notice The given path is not a valid pool or buffer.
     * @param path Pool or buffer address
     */
    error InvalidPath(address path);

    /**
     * @notice Thrown when a adding a pool or buffer for a given pair which had already been added to the registry.
     * @param path The address of the pool or buffer that was already added
     * @param tokenA The address of the first token in the pair
     * @param tokenB The address of the second token in the pair
     */
    error PathAlreadyAddedForPair(address path, address tokenA, address tokenB);

    /**
     * @notice Thrown when a removing a pool or buffer for a given pair which had not been added to the registry.
     * @param path The address of the pool or buffer being removed
     * @param tokenA The address of the first token in the pair
     * @param tokenB The address of the second token in the pair
     */
    error PathNotAddedForPair(address path, address tokenA, address tokenB);

    /**
     * @notice Returns the path address for a given token pair at a specific index.
     * @dev Safe version, reverts if the index is out of bounds.
     * @param tokenA The address of the first token in the pair
     * @param tokenB The address of the second token in the pair
     * @param index The index of the path in the list of paths for the token pair
     * @return The address of the path at the specified index for the token pair
     */
    function getPathAt(address tokenA, address tokenB, uint256 index) external view returns (address);

    /**
     * @notice Returns the path address for a given token pair at a specific index.
     * @dev Unsafe version, use only when index is known to be within bounds.
     * @param tokenA The address of the first token in the pair
     * @param tokenB The address of the second token in the pair
     * @param index The index of the path in the list of paths for the token pair
     * @return The address of the path at the specified index for the token pair
     */
    function getPathAtUnchecked(address tokenA, address tokenB, uint256 index) external view returns (address);

    /**
     * @notice Returns the number of paths registered for a given token pair.
     * @param tokenA The address of the first token in the pair
     * @param tokenB The address of the second token in the pair
     * @return The number of paths registered for the token pair
     */
    function getPathCount(address tokenA, address tokenB) external view returns (uint256);

    /**
     * @notice Returns the paths registered for a given token pair.
     * @param tokenA The address of the first token in the pair
     * @param tokenB The address of the second token in the pair
     * @return An array of path addresses registered for the token pair
     */
    function getPaths(address tokenA, address tokenB) external view returns (address[] memory);

    /**
     * @notice Returns true if a path is registered for a given token pair.
     * @param tokenA The address of the first token in the pair
     * @param tokenB The address of the second token in the pair
     * @return True if the path is registered for the given token pair, false otherwise
     */
    function hasPath(address tokenA, address tokenB, address path) external view returns (bool);

    /**
     * @notice Adds a pool or buffer to the registry for all token pairs they support.
     * @dev This function is permissioned. The call will revert if the path is already registered for the token pair.
     */
    function addPath(address path) external;

    function removePath(address path) external;
}
