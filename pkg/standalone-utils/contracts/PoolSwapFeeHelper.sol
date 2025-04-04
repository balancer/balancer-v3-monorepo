// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import { IPoolSwapFeeHelper } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IPoolSwapFeeHelper.sol";
import { SingletonAuthentication } from "@balancer-labs/v3-vault/contracts/SingletonAuthentication.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

contract PoolSwapFeeHelper is IPoolSwapFeeHelper, SingletonAuthentication {
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet private _pools;

    constructor(IVault vault) SingletonAuthentication(vault) {
        // solhint-disable-previous-line no-empty-blocks
    }

    /***************************************************************************
                                    Manage Pools
    ***************************************************************************/

    /// @inheritdoc IPoolSwapFeeHelper
    function addPools(address[] calldata newPools) external authenticate {
        uint256 length = newPools.length;

        for (uint256 i = 0; i < length; i++) {
            address pool = newPools[i];
            if (_pools.add(pool) == false) {
                revert PoolAlreadyInSwapFeeSet(pool);
            }

            // Pools cannot have a swap fee manager.
            if (getVault().getPoolRoleAccounts(pool).swapFeeManager != address(0)) {
                revert PoolHasSwapManager(pool);
            }

            emit PoolAddedToSwapFeeSet(pool);
        }
    }

    /// @inheritdoc IPoolSwapFeeHelper
    function removePools(address[] memory pools) public authenticate {
        uint256 length = pools.length;
        for (uint256 i = 0; i < length; i++) {
            address pool = pools[i];
            _ensureKnownPool(pool);
            _pools.remove(pool);

            emit PoolRemovedFromSwapFeeSet(pool);
        }
    }

    /// @inheritdoc IPoolSwapFeeHelper
    function setStaticSwapFeePercentage(address pool, uint256 swapFeePercentage) public authenticate {
        _ensureKnownPool(pool);

        getVault().setStaticSwapFeePercentage(pool, swapFeePercentage);
    }

    /***************************************************************************
                                    Getters                                
    ***************************************************************************/

    /// @inheritdoc IPoolSwapFeeHelper
    function getPoolCount() external view returns (uint256) {
        return _pools.length();
    }

    /// @inheritdoc IPoolSwapFeeHelper
    function hasPool(address pool) external view returns (bool) {
        return _pools.contains(pool);
    }

    /// @inheritdoc IPoolSwapFeeHelper
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

    function _ensureKnownPool(address pool) internal view {
        if (_pools.contains(pool) == false) {
            revert PoolNotInSwapFeeSet(pool);
        }
    }
}
