// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import { IPoolHelperCommon } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IPoolHelperCommon.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { OwnableAuthentication } from "./OwnableAuthentication.sol";

/// @notice Common code for helper functions that operate on a subset of pools.
abstract contract PoolHelperCommon is IPoolHelperCommon, OwnableAuthentication {
    using EnumerableSet for EnumerableSet.AddressSet;

    // Counter for generating unique pool set IDs. Must start at 1, since 0 is defined as invalid.
    uint256 private _nextPoolSetId = 1;

    // Mapping from pool set ID to the manager address.
    mapping(uint256 poolSetId => address manager) private _poolSetManagers;

    // Reverse lookup to find which set a given manager owns.
    // Note that this means an address may only control a single pool set.
    mapping(address manager => uint256 poolSetId) private _poolSetLookup;

    // Mapping from a pool set ID to the set of pools in that pool set.
    mapping(uint256 poolSetId => EnumerableSet.AddressSet pools) private _poolSets;

    // Ensure the explicit poolSetId (used in the admin interface) is valid.
    modifier withValidPoolSet(uint256 poolSetId) {
        _ensureValidPoolSet(poolSetId);
        _;
    }

    // Ensure the pool is in a set controlled by the caller. This is used in derived contracts.
    modifier withValidPoolForSender(address pool) {
        uint256 poolSetId = _getValidPoolSetId();
        _ensurePoolInSet(poolSetId, pool);
        _;
    }

    // Ensure the manager is non-zero, and not already a manager of another set.
    modifier withValidManager(address manager) {
        _ensureValidManager(manager);
        _;
    }

    constructor(IVault vault, address initialOwner) OwnableAuthentication(vault, initialOwner) {
        // solhint-disable-previous-line no-empty-blocks
    }

    /***************************************************************************
                                 Manage Pool Sets
    ***************************************************************************/

    /// @inheritdoc IPoolHelperCommon
    function createPoolSet(
        address initialManager
    ) external onlyOwner withValidManager(initialManager) returns (uint256) {
        return _createPoolSet(initialManager);
    }

    /// @inheritdoc IPoolHelperCommon
    function createPoolSet(
        address initialManager,
        address[] memory newPools
    ) external onlyOwner withValidManager(initialManager) returns (uint256 poolSetId) {
        poolSetId = _createPoolSet(initialManager);

        if (newPools.length > 0) {
            addPoolsToSet(poolSetId, newPools);
        }
    }

    function _createPoolSet(address initialManager) internal returns (uint256 poolSetId) {
        poolSetId = _nextPoolSetId++;

        // Add to forward and reverse mappings.
        _poolSetManagers[poolSetId] = initialManager;
        _poolSetLookup[initialManager] = poolSetId;

        emit PoolSetCreated(poolSetId, initialManager);
    }

    /// @inheritdoc IPoolHelperCommon
    function destroyPoolSet(uint256 poolSetId) external onlyOwner withValidPoolSet(poolSetId) {
        EnumerableSet.AddressSet storage poolSet = _poolSets[poolSetId];

        // Remove all pools from the set.
        uint256 numPools = poolSet.length();

        while (numPools > 0) {
            unchecked {
                --numPools;
            }

            address pool = poolSet.at(numPools);
            emit PoolRemovedFromSet(pool, poolSetId);

            poolSet.remove(pool);
        }

        // Remove the set itself.
        delete _poolSets[poolSetId];

        address manager = _poolSetManagers[poolSetId];

        // Also remove associated manager from both mappings.
        _poolSetManagers[poolSetId] = address(0);
        _poolSetLookup[manager] = 0;

        emit PoolSetDestroyed(poolSetId, manager);
    }

    /// @inheritdoc IPoolHelperCommon
    function transferPoolSetOwnership(address newManager) external withValidManager(newManager) {
        uint256 poolSetId = _getValidPoolSetId();

        _poolSetManagers[poolSetId] = newManager;

        // The "old" manager must be the current sender.
        _poolSetLookup[msg.sender] = 0;
        _poolSetLookup[newManager] = poolSetId;

        emit PoolSetOwnershipTransferred(poolSetId, msg.sender, newManager);
    }

    /***************************************************************************
                                   Manage Pools
    ***************************************************************************/

    /// @inheritdoc IPoolHelperCommon
    function addPoolsToSet(uint256 poolSetId, address[] memory newPools) public onlyOwner withValidPoolSet(poolSetId) {
        uint256 numPools = newPools.length;

        for (uint256 i = 0; i < numPools; i++) {
            address pool = newPools[i];

            // Ensure the address is a valid pool.
            if (vault.isPoolRegistered(pool) == false) {
                revert IVaultErrors.PoolNotRegistered(pool);
            }

            if (_poolSets[poolSetId].add(pool) == false) {
                revert PoolAlreadyInSet(pool, poolSetId);
            }

            // Call virtual function in case additional validation is needed.
            _validatePool(pool);

            emit PoolAddedToSet(pool, poolSetId);
        }
    }

    /// @inheritdoc IPoolHelperCommon
    function removePoolsFromSet(
        uint256 poolSetId,
        address[] memory pools
    ) public onlyOwner withValidPoolSet(poolSetId) {
        uint256 numPools = pools.length;

        for (uint256 i = 0; i < numPools; i++) {
            address pool = pools[i];

            if (_poolSets[poolSetId].remove(pool) == false) {
                revert PoolNotInSet(pool, poolSetId);
            }

            emit PoolRemovedFromSet(pool, poolSetId);
        }
    }

    /***************************************************************************
                                    Getters                                
    ***************************************************************************/

    /// @inheritdoc IPoolHelperCommon
    function getPoolSetIdForCaller() public view returns (uint256) {
        return _poolSetLookup[msg.sender];
    }

    /// @inheritdoc IPoolHelperCommon
    function getPoolSetIdForManager(address manager) public view returns (uint256) {
        return _poolSetLookup[manager];
    }

    /// @inheritdoc IPoolHelperCommon
    function getPoolCountForSet(uint256 poolSetId) external view withValidPoolSet(poolSetId) returns (uint256) {
        return _poolSets[poolSetId].length();
    }

    /// @inheritdoc IPoolHelperCommon
    function isValidPoolSetId(uint256 poolSetId) external view returns (bool) {
        return _poolSetManagers[poolSetId] != address(0);
    }

    /// @inheritdoc IPoolHelperCommon
    function isPoolInSet(address pool, uint256 poolSetId) external view withValidPoolSet(poolSetId) returns (bool) {
        return _poolSets[poolSetId].contains(pool);
    }

    /// @inheritdoc IPoolHelperCommon
    function getAllPoolsInSet(
        uint256 poolSetId
    ) external view withValidPoolSet(poolSetId) returns (address[] memory pools) {
        return _poolSets[poolSetId].values();
    }

    /// @inheritdoc IPoolHelperCommon
    function getPoolsInSet(
        uint256 poolSetId,
        uint256 from,
        uint256 to
    ) public view withValidPoolSet(poolSetId) returns (address[] memory pools) {
        uint256 spanLength = _poolSets[poolSetId].length();

        if (from > to || to > spanLength || from >= spanLength) {
            revert IndexOutOfBounds(poolSetId);
        }

        pools = new address[](to - from);
        for (uint256 i = from; i < to; i++) {
            pools[i - from] = _poolSets[poolSetId].at(i);
        }
    }

    /// @inheritdoc IPoolHelperCommon
    function getNextPoolSetId() external view returns (uint256) {
        return _nextPoolSetId;
    }

    /// @inheritdoc IPoolHelperCommon
    function getManagerForPoolSet(uint256 poolSetId) external view returns (address) {
        return _poolSetManagers[poolSetId];
    }

    /***************************************************************************
                                Internal functions                                
    ***************************************************************************/

    // Find and validate the poolSetId for the caller.
    function _getValidPoolSetId() internal view returns (uint256 poolSetId) {
        poolSetId = getPoolSetIdForCaller();

        if (poolSetId == 0) {
            revert SenderIsNotPoolSetManager();
        }
    }

    function _ensureValidManager(address manager) internal view {
        if (manager == address(0)) {
            revert InvalidPoolSetManager();
        }

        if (_poolSetLookup[manager] != 0) {
            revert PoolSetManagerNotUnique(manager);
        }
    }

    function _ensurePoolInSet(uint256 poolSetId, address pool) internal view {
        if (_poolSets[poolSetId].contains(pool) == false) {
            revert PoolNotInSet(pool, poolSetId);
        }
    }

    /// @dev Optional function called in `addPoolsToSet` for optional additional validation.
    function _validatePool(address pool) internal view virtual {
        // solhint-disable-previous-line no-empty-blocks
    }

    function _ensureValidPoolSet(uint256 poolSetId) internal view {
        if (poolSetId == 0 || _poolSetManagers[poolSetId] == address(0)) {
            revert InvalidPoolSetId(poolSetId);
        }
    }
}
