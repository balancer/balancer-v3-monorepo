// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { SingletonAuthentication } from "@balancer-labs/v3-vault/contracts/SingletonAuthentication.sol";

contract PauseHelper is SingletonAuthentication {
    using EnumerableSet for EnumerableSet.AddressSet;

    /**
     * @notice Revert if the pool is already in the list of pools
     * @param  pool Pool that tried to be added
     */
    error PoolExistInPausableSet(address pool);

    /**
     * @notice Revert if the pool is not in the list of pools
     * @param  pool Pool that not found
     */
    error PoolNotFoundInPausableSet(address pool);

    /// @notice An index is beyond the current bounds of the set.
    error IndexOutOfBounds();

    /**
     * @notice Emitted when a pool is added to the list of pools that can be paused
     * @param pool Pool that was added
     */
    event PoolAddedToPausableSet(address pool);

    /**
     * @notice Emitted when a pool is removed from the list of pools that can be paused
     * @param pool Pool that was removed
     */
    event PoolRemovedFromPausableSet(address pool);

    EnumerableSet.AddressSet private _poolSet;

    constructor(IVault vault) SingletonAuthentication(vault) {}

    // --------------------------  Manage Pools --------------------------

    /**
     * @notice Add pools to the list of pools that can be paused
     * @param newPools List of pools to add
     */
    function addPools(address[] calldata newPools) external authenticate {
        uint256 length = newPools.length;

        for (uint256 i = 0; i < length; i++) {
            if (_poolSet.add(newPools[i]) == false) {
                revert PoolExistInPausableSet(newPools[i]);
            }

            emit PoolAdded(newPools[i]);
        }
    }

    /**
     * @notice Remove pools from the list of pools that can be paused
     * @param pools List of pools to remove
     */
    function removePools(address[] memory pools) public authenticate {
        uint256 length = pools.length;
        for (uint256 i = 0; i < length; i++) {
            if (_poolSet.remove(pools[i]) == false) {
                revert PoolNotFoundInPausableSet(pools[i]);
            }

            emit PoolRemoved(pools[i]);
        }
    }

    /**
     * @notice Pause pools
     * @param pools List of pools to pause
     */
    function pausePools(address[] memory pools) public authenticate {
        uint256 length = pools.length;
        for (uint256 i = 0; i < length; i++) {
            if (_poolSet.contains(pools[i]) == false) {
                revert PoolNotFoundInPausableSet(pools[i]);
            }

            getVault().pausePool(pools[i]);
        }
    }

    // --------------------------  Getters --------------------------
    /**
     * @notice Get the number of pools
     * @return Number of pools
     */
    function getPoolsCount() external view returns (uint256) {
        return _poolSet.length();
    }

    /**
     * @notice Check if a pool is in the list of pools
     * @param pool Pool to check
     * @return True if the pool is in the list, false otherwise
     */
    function hasPool(address pool) external view returns (bool) {
        return _poolSet.contains(pool);
    }

    /**
     * @notice Get a range of pools
     * @param from Start index
     * @param to End index
     * @return pools List of pools
     */
    function getPools(uint256 from, uint256 to) public view returns (address[] memory pools) {
        uint256 poolLength = _poolSet.length();
        if (from > to || to > poolLength || from >= poolLength) {
            revert IndexOutOfBounds();
        }

        pools = new address[](to - from);
        for (uint256 i = from; i < to; i++) {
            pools[i - from] = _poolSet.at(i);
        }
    }
}
