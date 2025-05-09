// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import { IPoolHelperCommon } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IPoolHelperCommon.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { SingletonAuthentication } from "@balancer-labs/v3-vault/contracts/SingletonAuthentication.sol";

/// @notice Common code for helper functions that operate on a subset of pools.
abstract contract PoolHelperCommon is IPoolHelperCommon, SingletonAuthentication {
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet internal _pools;

    constructor(IVault vault) SingletonAuthentication(vault) {
        // solhint-disable-previous-line no-empty-blocks
    }

    /***************************************************************************
                                    Manage Pools
    ***************************************************************************/

    /// @inheritdoc IPoolHelperCommon
    function addPools(address[] calldata newPools) external authenticate {
        uint256 length = newPools.length;

        for (uint256 i = 0; i < length; i++) {
            address pool = newPools[i];

            // Ensure the address is a valid pool.
            if (getVault().isPoolRegistered(pool) == false) {
                revert IVaultErrors.PoolNotRegistered(pool);
            }

            // Call virtual function in case additional validation is needed.
            _validatePool(pool);

            if (_pools.add(pool) == false) {
                revert PoolAlreadyInSet(pool);
            }

            emit PoolAddedToSet(pool);
        }
    }

    /// @inheritdoc IPoolHelperCommon
    function removePools(address[] memory pools) public authenticate {
        uint256 length = pools.length;
        for (uint256 i = 0; i < length; i++) {
            address pool = pools[i];
            if (_pools.remove(pool) == false) {
                revert PoolNotInSet(pool);
            }

            emit PoolRemovedFromSet(pool);
        }
    }

    /***************************************************************************
                                    Getters                                
    ***************************************************************************/

    /// @inheritdoc IPoolHelperCommon
    function getPoolCount() external view returns (uint256) {
        return _pools.length();
    }

    /// @inheritdoc IPoolHelperCommon
    function hasPool(address pool) external view returns (bool) {
        return _pools.contains(pool);
    }

    /// @inheritdoc IPoolHelperCommon
    function getPools(uint256 from, uint256 to) public view returns (address[] memory pools) {
        uint256 poolLength = _pools.length();
        if (from > to || to > poolLength || from >= poolLength) {
            revert IndexOutOfBounds();
        }

        pools = new address[](to - from);
        for (uint256 i = from; i < to; i++) {
            pools[i - from] = _pools.at(i);
        }
    }

    /***************************************************************************
                                Internal functions                                
    ***************************************************************************/

    function _ensurePoolAdded(address pool) internal view {
        if (_pools.contains(pool) == false) {
            revert PoolNotInSet(pool);
        }
    }

    /// @dev Optional function called in addPools for additional validation.
    function _validatePool(address pool) internal view virtual {
        // solhint-disable-previous-line no-empty-blocks
    }
}
