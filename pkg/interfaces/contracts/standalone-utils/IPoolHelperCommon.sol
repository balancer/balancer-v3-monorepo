// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

/// @notice Common interface for helper functions that operate on a subset of pools.
interface IPoolHelperCommon {
    /**
     * @notice The owner created a new pool set.
     * @dev Pools are organized into separate sets, controlled by a manager, which can be changed independently.
     * @param poolSetId Id of the set with which the pool is associated
     * @param initialManager Address of the pool set manager
     */
    event PoolSetCreated(uint256 indexed poolSetId, address indexed initialManager);

    /**
     * @notice The owner destroyed a pool set.
     * @param poolSetId Id of the set with which the pool is associated
     * @param manager The address of the set's last manager
     */
    event PoolSetDestroyed(uint256 indexed poolSetId, address indexed manager);

    /**
     * @notice The owner added a pool to the given set.
     * @param pool Address of the pool that was added
     * @param poolSetId Id of the set with which the pool is associated
     */
    event PoolAddedToSet(address indexed pool, uint256 indexed poolSetId);

    /**
     * @notice The owner removed a pool from the given set.
     * @param poolSetId Id of the set with which the pool is associated
     * @param pool Address of the pool that was removed
     */
    event PoolRemovedFromSet(address indexed pool, uint256 indexed poolSetId);

    /**
     * @notice The current manager of a pool set transferred ownership to a new address.
     * @dev Managers can only control one pool set. Transfers to existing managers of other sets will revert.
     * @param poolSetId Id of the set with which the pool is associated
     * @param oldManager Address of the previous manager
     * @param newManager Address of the new manager
     */
    event PoolSetOwnershipTransferred(
        uint256 indexed poolSetId,
        address indexed oldManager,
        address indexed newManager
    );

    /**
     * @notice Cannot add a pool that is already there.
     * @param pool Address of the pool being added
     * @param poolSetId Id of the set with which the pool is associated
     */
    error PoolAlreadyInSet(address pool, uint256 poolSetId);

    /**
     * @notice Cannot remove a pool that was not added.
     * @param pool Address of the pool being removed
     * @param poolSetId Id of the set with which the pool is associated
     */
    error PoolNotInSet(address pool, uint256 poolSetId);

    /**
     * @notice Pool set id associated with an operation is invalid.
     * @dev This can mean the value is invalid, or it was never created, or it was destroyed.
     * @param poolSetId The id of the invalid set
     */
    error InvalidPoolSetId(uint256 poolSetId);

    /// @notice The initial manager of a pool set cannot be zero.
    error InvalidPoolSetManager();

    /**
     * @notice Pool set managers can only manage a single pool set.
     * @dev Otherwise, the contract would not be able to determine the correct pool set from the caller's address.
     * @param poolSetManager Address of the manager that is already assigned to another pool set id
     */
    error PoolSetManagerNotUnique(address poolSetManager);

    /// @notice Permissioned operations on pools can only be performed by the pool set manager.
    error SenderIsNotPoolSetManager();

    /**
     * @notice An index is beyond the current bounds of the set.
     * @param poolSetId Id of the set involved in the operation
     */
    error IndexOutOfBounds(uint256 poolSetId);

    /***************************************************************************
                                 Manage Pool Sets
    ***************************************************************************/

    /**
     * @notice Create a new set with an initial manager, optionally initialized with a set of pools.
     * @dev The `newPools` list can be empty, in which case this will only create the set. Pools can then be
     * added with `addPoolsToSet`, or removed with `removePoolsFromSet`. This is a permissioned function.
     * Only the current owner of the helper contract (e.g., Maxis) may create new sets. Also reverts if the
     * initial manager address is zero or already a manager of another pool set.
     *
     * @param initialManager Address of the account authorized to perform operations on the set
     * @param newPools Set of pools to add to the set
     */
    function createPoolSet(address initialManager, address[] memory newPools) external returns (uint256 poolSetId);

    /**
     * @notice Create a new empty set with an initial manager.
     * @dev Convenience function to create a pool set with no initial pools. Also reverts if the initial manager
     * address is zero or already a manager of another pool set.
     *
     * @param initialManager Address of the account authorized to perform operations on the set
     */
    function createPoolSet(address initialManager) external returns (uint256 poolSetId);

    /**
     * @notice Simple way to remove an entire set of pools from control of the helper function.
     * @dev This is a permissioned function. Only the current owner of the helper contract (e.g., Maxis)
     * may destroy sets, effectively removing control of any pools in the set from the associated manager.
     * Also reverts if the poolSetId is not valid.
     *
     * @param poolSetId Id of the set being destroyed
     */
    function destroyPoolSet(uint256 poolSetId) external;

    /**
     * @notice Transfer ownership of a pool set from the current manager to a new manager.
     * @dev This is a permissioned function. Only the current manager of a set can call this to set a new manager.
     * Since managers can only control a single set, there is no need to specify the id in the call. Note that this
     * is a one-step migration. If it is done incorrectly, effective control of the set is lost, and the owner of this
     * contract will need to destroy the old set and create a new one with the correct initial manager. Also reverts
     * if the new manager address is zero or already the manager of a pool set.
     *
     * @param newManager The address of the new manager
     */
    function transferPoolSetOwnership(address newManager) external;

    /***************************************************************************
                                   Manage Pools
    ***************************************************************************/

    /**
     * @notice Add pools to the set of pools controlled by this helper contract.
     * @dev This is a permissioned function. Only the current owner of the helper contract (e.g., Maxis)
     * may add pools to a set. Also reverts if the poolSetId is not valid.
     *
     * @param newPools List of pools to add
     * @param poolSetId Id of the set to which the new pools belong
     */
    function addPoolsToSet(uint256 poolSetId, address[] memory newPools) external;

    /**
     * @notice Remove pools from the set of pools controlled by this helper contract.
     * @dev This is a permissioned function. Only the current owner of the helper contract (e.g., Maxis)
     * may remove pools from a set. Also reverts if the poolSetId is not valid.
     *
     * @param pools List of pools to remove from the set
     * @param poolSetId Id of the set to which the pools belong
     */
    function removePoolsFromSet(uint256 poolSetId, address[] memory pools) external;

    /***************************************************************************
                                    Getters                                
    ***************************************************************************/

    /**
     * @notice Get the pool set id associated with the caller.
     * @return poolSetId The numeric pool set id, or zero if the caller is not a pool set manager
     */
    function getPoolSetIdForCaller() external view returns (uint256 poolSetId);

    /**
     * @notice Get the pool set id associated with a given manager address.
     * @return poolSetId The numeric pool set id, or zero if the address given is not a pool set manager
     */
    function getPoolSetIdForManager(address manager) external view returns (uint256 poolSetId);

    /**
     * @notice Get the number of pools associated with the given set.
     * @dev Needed to support pagination in case the set is too large to process in a single transaction.
     * Reverts if the poolSetId is not valid.
     *
     * @param poolSetId Id of the set containing the pools
     * @return poolCount The current number of pools in the set
     */
    function getPoolCountForSet(uint256 poolSetId) external view returns (uint256 poolCount);

    /**
     * @notice Check whether a poolSetId has been created.
     * @param poolSetId Id of the set containing the pools
     * @return isValid True if the poolSetId exists
     */
    function isValidPoolSetId(uint256 poolSetId) external view returns (bool isValid);

    /**
     * @notice Check whether a pool is in the set of pools.
     * @dev Reverts if the poolSetId is not valid.
     * @param pool Address of the pool to check
     * @param poolSetId Id of the set containing the pools
     * @return poolInSet True if the pool is in the given set, false otherwise
     */
    function isPoolInSet(address pool, uint256 poolSetId) external view returns (bool poolInSet);

    /**
     * @notice Get the full set of pools from a given set.
     * @dev Reverts if the poolSetId is not valid.
     * @param poolSetId Id of the set containing the pools
     * @return pools List of pools
     */
    function getAllPoolsInSet(uint256 poolSetId) external view returns (address[] memory pools);

    /**
     * @notice Get a range of pools from a given set.
     * @dev Indexes are 0-based and [start, end) (i.e., inclusive of `start`; exclusive of `end`).
     * Reverts if the poolSetId is not valid.
     *
     * @param poolSetId Id of the set containing the pools
     * @param from Start index
     * @param to End index
     * @return pools List of pools
     */
    function getPoolsInSet(uint256 poolSetId, uint256 from, uint256 to) external view returns (address[] memory pools);

    /**
     * @notice Utility function to predict the next pool set id.
     * @return nextPoolSetId The pool set id that will be used on the next call of `createPoolSet`
     */
    function getNextPoolSetId() external view returns (uint256 nextPoolSetId);

    /**
     * @notice Get the manager address associated with a given poolSetId.
     * @param poolSetId Id of the set containing the pools
     * @return manager The address of the manager of the given poolSetId, or zero if the poolSetId is unassigned
     */
    function getManagerForPoolSet(uint256 poolSetId) external view returns (address manager);
}
