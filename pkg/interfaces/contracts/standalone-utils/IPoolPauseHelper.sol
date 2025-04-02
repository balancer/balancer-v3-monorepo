// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

interface IPoolPauseHelper {
    /**
     * @notice Cannot add a pool that is already there.
     * @param pool Address of the pool being added
     */
    error PoolAlreadyInPausableSet(address pool);

    /**
     * @notice Cannot remove a pool that was not added.
     * @param pool Address of the pool being removed
     */
    error PoolNotInPausableSet(address pool);

    /// @notice An index is beyond the current bounds of the set.
    error IndexOutOfBounds();

    /**
     * @notice Emitted when a pool is added to the list of pools that can be paused.
     * @param pool Address of the pool that was added
     */
    event PoolAddedToPausableSet(address pool);

    /**
     * @notice Emitted when a pool is removed from the list of pools that can be paused.
     * @param pool Address of the pool that was removed
     */
    event PoolRemovedFromPausableSet(address pool);

    /***************************************************************************
                                    Manage Pools
    ***************************************************************************/

    /**
     * @notice Add pools to the list of pools that can be paused.
     * @dev This is a permissioned function. Only authorized accounts (e.g., monitoring service providers) may add
     * pools to the pause list.
     *
     * @param newPools List of pools to add
     */
    function addPools(address[] calldata newPools) external;

    /**
     * @notice Remove pools from the list of pools that can be paused.
     * @dev This is a permissioned function. Only authorized accounts (e.g., monitoring service providers) may remove
     * pools from the pause list.
     *
     * @param pools List of pools to remove
     */
    function removePools(address[] memory pools) external;

    /**
     * @notice Pause a set of pools.
     * @dev This is a permissioned function. Governance must first grant this contract permission to call `pausePool`
     * on the Vault, then grant another account permission to call `pausePools` here. Note that this is not necessarily
     * the same account that can add or remove pools from the pausable list.
     *
     * Note that there is no `unpause`. This is a helper contract designed to react quickly to emergencies. Unpausing
     * is a more deliberate action that should be performed by accounts approved by governance for this purpose, or by
     * the individual pools' pause managers.
     *
     * @param pools List of pools to pause
     */
    function pausePools(address[] memory pools) external;

    /***************************************************************************
                                    Getters                                
    ***************************************************************************/

    /**
     * @notice Get the number of pools.
     * @dev Needed to support pagination in case the list is too long to process in a single transaction.
     * @return poolCount The current number of pools in the pausable list
     */
    function getPoolCount() external view returns (uint256);

    /**
     * @notice Check whether a pool is in the list of pausable pools.
     * @param pool Pool to check
     * @return isPausable True if the pool is in the list, false otherwise
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
