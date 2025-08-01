// SPDX-License-Identifier: GPL-3.0-or-later

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { IBatchRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IBatchRouter.sol";

pragma solidity ^0.8.24;

interface ITokenPairRegistry {
    /**
     * @notice Emitted when a new token pair is added to the registry.
     * @param tokenIn The address of the first token in the pair
     * @param tokenOut The address of the second token in the pair
     * @param pathsLength The number of paths added for the token pair
     */
    event PathAdded(address indexed tokenIn, address indexed tokenOut, uint256 pathsLength);

    /**
     * @notice Emitted when an existing token pair is removed from the registry.
     * @param tokenIn The address of the first token in the pair
     * @param tokenOut The address of the second token in the pair
     * @param pathsLength The number of paths added for the token pair
     */
    event PathRemoved(address indexed tokenIn, address indexed tokenOut, uint256 pathsLength);

    error BufferNotInitialized(address buffer);

    /**
     * @notice The given address is not a valid pool or buffer.
     * @param path Pool or buffer address
     */
    error InvalidSimplePath(address path);

    error InvalidBufferPath(address buffer, address tokenIn, address tokenOut);

    error IndexOutOfBounds();

    /**
     * @notice Returns the path address for a given token pair at a specific index.
     * @dev Safe version, reverts if the index is out of bounds.
     * @param tokenA The address of the first token in the pair
     * @param tokenB The address of the second token in the pair
     * @param index The index of the path in the list of paths for the token pair
     * @return The address of the path at the specified index for the token pair
     */
    function getPathAt(address tokenA, address tokenB, uint256 index) external view returns (IBatchRouter.SwapPathStep[] memory);

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
    function getPaths(address tokenA, address tokenB) external view returns (IBatchRouter.SwapPathStep[][] memory);

    /**
     * @notice Adds a pool or buffer to the registry for all token pairs they support.
     * @dev This function is permissioned. The call will revert if the path is already registered for the token pair.
     */
    function addSimplePath(address path) external;

    /**
     * @notice Removes a pool or buffer from the registry for all token pairs they support.
     * @dev This function is permissioned. The call will revert if the path is not registered for the token pair.
     */
    function removeSimplePath(address path) external;
}
