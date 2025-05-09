// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

/// @notice Common interface for helper functions that operate on a subset of pools.
interface IPoolHelperCommon {
    /**
     * @notice Emitted when a pool is added to the set of pools that can be controlled by the helper contract.
     * @param pool Address of the pool that was added
     */
    event PoolAddedToSet(address pool);

    /**
     * @notice Emitted when a pool is removed from the set of pools that can be controlled by the helper contract.
     * @param pool Address of the pool that was removed
     */
    event PoolRemovedFromSet(address pool);

    /**
     * @notice Cannot add a pool that is already there.
     * @param pool Address of the pool being added
     */
    error PoolAlreadyInSet(address pool);

    /**
     * @notice Cannot remove a pool that was not added.
     * @param pool Address of the pool being removed
     */
    error PoolNotInSet(address pool);

    /// @notice An index is beyond the current bounds of the set.
    error IndexOutOfBounds();

    /***************************************************************************
                                    Manage Pools
    ***************************************************************************/

    /**
     * @notice Add pools to the set of pools controlled by this helper contract.
     * @dev This is a permissioned function. Only authorized accounts (e.g., monitoring service providers) may add
     * pools to the set.
     *
     * @param newPools List of pools to add
     */
    function addPools(address[] calldata newPools) external;

    /**
     * @notice Remove pools from the set of pools controlled by this helper contract.
     * @dev This is a permissioned function. Only authorized accounts (e.g., monitoring service providers) may remove
     * pools from the set.
     *
     * @param pools List of pools to remove
     */
    function removePools(address[] memory pools) external;

    /***************************************************************************
                                    Getters                                
    ***************************************************************************/

    /**
     * @notice Get the number of pools.
     * @dev Needed to support pagination in case the set is too large to process in a single transaction.
     * @return poolCount The current number of pools in the set
     */
    function getPoolCount() external view returns (uint256);

    /**
     * @notice Check whether a pool is in the set of pools.
     * @param pool Pool to check
     * @return isPausable True if the pool is in the set, false otherwise
     */
    function hasPool(address pool) external view returns (bool);

    /**
     * @notice Get a range of pools.
     * @dev Indexes are 0-based and [start, end) (i.e., inclusive of `start`; exclusive of `end`).
     * @param from Start index
     * @param to End index
     * @return pools List of pools
     */
    function getPools(uint256 from, uint256 to) external view returns (address[] memory pools);
}
