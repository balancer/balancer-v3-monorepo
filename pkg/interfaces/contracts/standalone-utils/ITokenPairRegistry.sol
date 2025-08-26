// SPDX-License-Identifier: GPL-3.0-or-later

import { SwapPathStep } from "../vault/BatchRouterTypes.sol";

pragma solidity ^0.8.24;

interface ITokenPairRegistry {
    /**
     * @notice Emitted when a new token pair is added to the registry.
     * @param tokenIn The address of the input token in the pair
     * @param tokenOut The address of the output token in the pair
     * @param pathsLength The number of paths added for the token pair
     */
    event PathAdded(address indexed tokenIn, address indexed tokenOut, uint256 pathsLength);

    /**
     * @notice Emitted when an existing token pair is removed from the registry.
     * @param tokenIn The address of the input token in the pair
     * @param tokenOut The address of the output token in the pair
     * @param pathsLength The number of paths associated with the token pair after the removal
     */
    event PathRemoved(address indexed tokenIn, address indexed tokenOut, uint256 pathsLength);

    /**
     * @notice The given buffer address does not correspond to an initialized buffer.
     * @param buffer The address of the uninitialized buffer
     */
    error BufferNotInitialized(address buffer);

    /// @notice The path to add cannot be empty.
    error EmptyPath();

    /**
     * @notice The given address is not a valid pool or buffer.
     * @param path Pool or buffer address
     */
    error InvalidSimplePath(address path);

    /**
     * @notice The given pool or buffer is not registered as a path for the token pair.
     * @param poolOrBuffer The address of the pool or buffer
     * @param tokenIn The address of the input token in the pair
     * @param tokenOut The address of the output token in the pair
     */
    error InvalidRemovePath(address poolOrBuffer, address tokenIn, address tokenOut);

    /**
     * @notice The output token does not match the expected address in a wrap or unwrap operation.
     * @param buffer The address of the buffer
     * @param tokenIn The address of the input token in the pair
     * @param tokenOut The address of the output token in the pair
     */
    error InvalidBufferPath(address buffer, address tokenIn, address tokenOut);

    /// @notice Attempted to remove a path at an index beyond the registered length.
    error IndexOutOfBounds();

    /**
     * @notice Returns the path for a given token pair at a specific index.
     * @dev Safe version; reverts if the index is out of bounds.
     * @param tokenIn The address of the input token in the pair
     * @param tokenOut The address of the output token in the pair
     * @param index The index of the path in the list of paths for the token pair
     * @return The path at the specified index for the token pair
     */
    function getPathAt(address tokenIn, address tokenOut, uint256 index) external view returns (SwapPathStep[] memory);

    /**
     * @notice Returns the number of paths registered for a given token pair.
     * @param tokenIn The address of the input token in the pair
     * @param tokenOut The address of the output token in the pair
     * @return The number of paths registered for the token pair
     */
    function getPathCount(address tokenIn, address tokenOut) external view returns (uint256);

    /**
     * @notice Returns the paths registered for a given token pair.
     * @param tokenIn The address of the input token in the pair
     * @param tokenOut The address of the output token in the pair
     * @return An array of path addresses registered for the token pair
     */
    function getPaths(address tokenIn, address tokenOut) external view returns (SwapPathStep[][] memory);

    /**
     * @notice Adds an arbitrary path between `tokenIn` and the last step's `tokenOut` to the registry.
     * @dev This function is permissioned. Use it to register boosted pool paths with leading / trailing buffer steps.
     * The registry will validate that each step is valid (i.e. each pool step contains the `tokenIn` and `tokenOut`,
     * and each buffer step has the correct wrapped / underlying token).
     *
     * @param tokenIn The address of the input token in the pair
     * @param steps An array of `SwapPathStep` structs representing the path steps to reach the output token
     */
    function addPath(address tokenIn, SwapPathStep[] memory steps) external;

    /**
     * @notice Adds a pool or buffer to the registry with all token pairs it supports.
     * @dev This function is permissioned.
     * @param poolOrBuffer The address of the pool or buffer
     */
    function addSimplePath(address poolOrBuffer) external;

    /**
     * @notice Removes an arbitrary path from the registry at a given index.
     * @dev This function is permissioned.
     * @param tokenIn The address of the input token in the pair
     * @param tokenOut The address of the output token in the pair
     * @param index The index of the path to remove in the list of paths for the token pair
     */
    function removePathAtIndex(address tokenIn, address tokenOut, uint256 index) external;

    /**
     * @notice Removes all token paths registered for a given pool or buffer.
     * @dev This function is permissioned.
     * @param poolOrBuffer The address of the pool or buffer
     */
    function removeSimplePath(address poolOrBuffer) external;
}
