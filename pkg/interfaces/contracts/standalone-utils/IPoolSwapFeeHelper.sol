// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

/**
 * @notice Maintain a set of pools whose static swap fee percentages can be changed from here, vs. from the Vault.
 * @dev Governance can add a set of pools to this contract, then grant swap fee setting permission to accounts on this
 * contract, which allows greater granularity than setting the permission directly on the Vault.
 *
 * Note that governance must grant this contract permission to set swap fees from the Vault, and only pools that
 * allow governance to set fees can be added (i.e., they must not have swap managers).
 */
interface IPoolSwapFeeHelper {
    /**
     * @notice Cannot add a pool that is already there.
     * @param pool Address of the pool being added
     */
    error PoolAlreadyInSwapFeeSet(address pool);

    /**
     * @notice Cannot remove a pool that was not added.
     * @param pool Address of the pool being removed
     */
    error PoolNotInSwapFeeSet(address pool);

    /**
     * @notice Cannot add a pool that has a swap manager.
     * @dev The swap manager is an exclusive role. If it is set to a non-zero value during pool registration,
     * only the swap manager can change the fee. This helper can only set fees on pools that allow governance
     * to grant this permission.
     *
     * @param pool Address of the pool being added
     */
    error PoolHasSwapManager(address pool);

    /// @notice An index is beyond the current bounds of the set.
    error IndexOutOfBounds();

    /**
     * @notice Emitted when a pool is added to the list of pools whose swap fee can be changed.
     * @param pool Address of the pool that was added
     */
    event PoolAddedToSwapFeeSet(address pool);

    /**
     * @notice Emitted when a pool is removed from the list of pools whose swap fee can be changed.
     * @param pool Address of the pool that was removed
     */
    event PoolRemovedFromSwapFeeSet(address pool);

    /***************************************************************************
                                    Manage Pools
    ***************************************************************************/

    /**
     * @notice Add pools to the list of pools whose swap fee can be changed.
     * @dev This is a permissioned function. Only authorized accounts (e.g., dynamic fee service providers) may add
     * pools to the set.
     *
     * @param newPools List of pools to add
     */
    function addPools(address[] calldata newPools) external;

    /**
     * @notice Remove pools from the list of pools whose swap fee can be changed.
     * @dev This is a permissioned function. Only authorized accounts (e.g., dynamic fee service providers) may remove
     * pools from the set.
     *
     * @param pools List of pools to remove
     */
    function removePools(address[] memory pools) external;

    /**
     * @notice Set the static swap fee percentage on a given pool.
     * @dev This is a permissioned function. Governance must grant this contract permission to call
     * `setStaticSwapFeePercentage` on the Vault. Note that since the swap manager is an exclusive role, the swap fee
     * cannot be changed by governance if it is set, and the pool cannot be added to the set.
     *
     * @param pool The address of the pool
     * @param swapFeePercentage The new swap fee percentage
     */
    function setStaticSwapFeePercentage(address pool, uint256 swapFeePercentage) external;

    /***************************************************************************
                                    Getters                                
    ***************************************************************************/

    /**
     * @notice Get the number of pools.
     * @dev Needed to support pagination in case the list is too long to process in a single transaction.
     * @return poolCount The current number of pools whose swap fee can be changed from this contract
     */
    function getPoolCount() external view returns (uint256);

    /**
     * @notice Check whether a pool is in the set of pools whose swap fee can be changed.
     * @param pool Address of the pool
     * @return isPausable True if the pool is in the set
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
