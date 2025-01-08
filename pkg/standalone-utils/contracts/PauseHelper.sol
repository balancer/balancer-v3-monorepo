// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { SingletonAuthentication } from "@balancer-labs/v3-vault/contracts/SingletonAuthentication.sol";

contract PauseHelper is SingletonAuthentication {
    using EnumerableSet for EnumerableSet.AddressSet;

    event PoolAdded(address pool);
    event PoolRemoved(address pool);

    EnumerableSet.AddressSet private _poolsSet;

    constructor(IVault vault) SingletonAuthentication(vault) {}

    // --------------------------  Manage Pools --------------------------

    /**
     * @notice Add pools to the list of pools that can be paused
     * @param newPools List of pools to add
     */
    function addPools(address[] calldata newPools) external authenticate {
        uint256 length = newPools.length;

        for (uint256 i = 0; i < length; i++) {
            _poolsSet.add(newPools[i]);

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
            _poolsSet.remove(pools[i]);

            emit PoolRemoved(pools[i]);
        }
    }

    /**
     * @notice Pause pools
     * @param pools List of pools to pause
     */
    function pause(address[] memory pools) public authenticate {
        uint256 length = pools.length;
        for (uint256 i = 0; i < length; i++) {
            require(_poolsSet.contains(pools[i]), "Pool is not in the list of pools");

            getVault().pausePool(pools[i]);
        }
    }

    // --------------------------  Getters --------------------------
    /**
     * @notice Get the number of pools
     * @return Number of pools
     */
    function getPoolsCount() external view returns (uint256) {
        return _poolsSet.length();
    }

    /**
     * @notice Check if a pool is in the list of pools
     * @param pool Pool to check
     * @return True if the pool is in the list, false otherwise
     */
    function hasPool(address pool) external view returns (bool) {
        return _poolsSet.contains(pool);
    }

    /**
     * @notice Get a range of pools
     * @param from Start index
     * @param to End index
     * @return pools List of pools
     */
    function getPools(uint256 from, uint256 to) public view returns (address[] memory pools) {
        uint256 poolLength = _poolsSet.length();
        require(from <= to, "'From' must be less than 'to'");
        require(to <= poolLength, "'To' must be less than or eq the number of pools");
        require(from < poolLength, "'From' must be less than the number of pools");

        pools = new address[](to - from);
        for (uint256 i = from; i < to; i++) {
            pools[i - from] = _poolsSet.at(i);
        }
    }
}
