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
    error PoolAlreadyInPausableSet(address pool);

    /**
     * @notice Revert if the pool is not in the list of pools
     * @param  pool Pool that not found
     */
    error PoolNotInPausableSet(address pool);

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

    EnumerableSet.AddressSet private _pausablePools;

    constructor(IVault vault) SingletonAuthentication(vault) {
        // solhint-disable-previous-line no-empty-blocks
    }

    /***************************************************************************
                                                      Manage Pools
    ***************************************************************************/

    /**
     * @notice Add pools to the list of pools that can be paused.
     * @dev This is a permissioned function. Only authorized accounts (e.g., monitoring service providers) may add
     * pools to the pause list.
     * @param newPools List of pools to add
     */
    function addPools(address[] calldata newPools) external authenticate {
        uint256 length = newPools.length;

        for (uint256 i = 0; i < length; i++) {
            if (_pausablePools.add(newPools[i]) == false) {
                revert PoolAlreadyInPausableSet(newPools[i]);
            }

            emit PoolAddedToPausableSet(newPools[i]);
        }
    }

    /**
     * @notice Remove pools from the list of pools that can be paused.
     * @dev This is a permissioned function. Only authorized accounts (e.g., monitoring service providers) may remove
     * pools from the pause list.
     * @param pools List of pools to remove
     */
    function removePools(address[] memory pools) public authenticate {
        uint256 length = pools.length;
        for (uint256 i = 0; i < length; i++) {
            if (_pausablePools.remove(pools[i]) == false) {
                revert PoolNotInPausableSet(pools[i]);
            }

            emit PoolRemovedFromPausableSet(pools[i]);
        }
    }

    /**
     * @notice Pause a set of pools.
     * @dev This is a permissioned function. Governance must first grant this contract permission to call `pausePool`
     * on the Vault, then grant another account permission to call `pausePools` here. Note that this is not necessarily
     * the same account that can add or remove pools from the pausable list.
     *
     * Note that there is no `unpause`. This is a helper contract designed to react quickly to emergencies. Unpausing
     * is a more deliberate action that should be performed by accounts approved by governance for this purpose, or by
     * the individual pools' pause managers.
     * @param pools List of pools to pause
     */
    function pausePools(address[] memory pools) public authenticate {
        uint256 length = pools.length;
        for (uint256 i = 0; i < length; i++) {
            if (_pausablePools.contains(pools[i]) == false) {
                revert PoolNotInPausableSet(pools[i]);
            }

            getVault().pausePool(pools[i]);
        }
    }

    /***************************************************************************
                               Getters
    ***************************************************************************/

    /**
     * @notice Get the number of pools.
     * @dev Needed to support pagination in case the list is too long to process in a single transaction.
     * @return poolCount The current number of pools in the pausable list
     */
    function getPoolsCount() external view returns (uint256) {
        return _pausablePools.length();
    }

    /**
     * @notice Check whether a pool is in the list of pausable pools.
     * @param pool Pool to check
     * @return isPausable True if the pool is in the list, false otherwise
     */
    function hasPool(address pool) external view returns (bool) {
        return _pausablePools.contains(pool);
    }

    /**
     * @notice Get a range of pools
     * @param from Start index
     * @param to End index
     * @return pools List of pools
     */
    function getPools(uint256 from, uint256 to) public view returns (address[] memory pools) {
        uint256 poolLength = _pausablePools.length();
        if (from > to || to > poolLength || from >= poolLength) {
            revert IndexOutOfBounds();
        }

        pools = new address[](to - from);
        for (uint256 i = from; i < to; i++) {
            pools[i - from] = _pausablePools.at(i);
        }
    }
}
