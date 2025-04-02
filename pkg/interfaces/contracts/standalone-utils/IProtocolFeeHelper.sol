// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

interface IProtocolFeeHelper {
    /**
     * @notice Cannot add a pool that is already there.
     * @param pool Address of the pool being added
     */
    error PoolAlreadyInProtocolFeeSet(address pool);

    /**
     * @notice Cannot remove a pool that was not added.
     * @param pool Address of the pool being removed
     */
    error PoolNotInProtocolFeeSet(address pool);

    /// @notice An index is beyond the current bounds of the set.
    error IndexOutOfBounds();

    /**
     * @notice Emitted when a pool is added to the list of pools whose protocol fees can be set.
     * @param pool Address of the pool that was added
     */
    event PoolAddedToProtocolFeeSet(address pool);

    /**
     * @notice Emitted when a pool is removed from the list of pools whose protocol fees can be set.
     * @param pool Address of the pool that was removed
     */
    event PoolRemovedFromProtocolFeeSet(address pool);

    /***************************************************************************
                                    Manage Pools
    ***************************************************************************/

    /**
     * @notice Add pools to the list of pools whose protocol fees can be set.
     * @dev This is a permissioned function. Only authorized accounts may pools to the set.
     *
     * @param newPools List of pools to add
     */
    function addPools(address[] calldata newPools) external;

    /**
     * @notice Remove pools from the list of pools whose protocol fees can be set.
     * @dev This is a permissioned function. Only authorized accounts may remove pools from the set.
     *
     * @param pools List of pools to remove
     */
    function removePools(address[] memory pools) external;

    /**
     * @notice Set the protocol swap fee for a pool.
     * @dev This contract must be granted permission to set swap and yield protocol fees, but governance can
     * independently grant permission to call the swap and yield fee setters.
     *
     * @param pool The address of the pool
     * @param protocolSwapFeePercentage The new protocol swap fee percentage
     */
    function setProtocolSwapFeePercentage(address pool, uint256 protocolSwapFeePercentage) external;

    /**
     * @notice Set the protocol yield fee for a pool.
     * @dev This contract must be granted permission to set swap and yield protocol fees, but governance can
     * independently grant permission to call the swap and yield fee setters.
     *
     * @param pool The address of the pool
     * @param protocolYieldFeePercentage The new protocol yield fee percentage
     */
    function setProtocolYieldFeePercentage(address pool, uint256 protocolYieldFeePercentage) external;

    /***************************************************************************
                                    Getters                                
    ***************************************************************************/

    /**
     * @notice Get the number of pools.
     * @dev Needed to support pagination in case the list is too long to process in a single transaction.
     * @return poolCount The current number of pools in the set
     */
    function getPoolCount() external view returns (uint256);

    /**
     * @notice Check whether a pool is in the set of pools.
     * @param pool Pool to check
     * @return isProtocolFee True if the pool is in the list, false otherwise
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
