// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { IPausePoolHelper } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IPausePoolHelper.sol";
import { SingletonAuthentication } from "@balancer-labs/v3-vault/contracts/SingletonAuthentication.sol";

contract PausePoolHelper is IPausePoolHelper, SingletonAuthentication {
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet private _pausablePools;

    constructor(IVault vault) SingletonAuthentication(vault) {
        // solhint-disable-previous-line no-empty-blocks
    }

    /***************************************************************************
                                    Manage Pools
    ***************************************************************************/

    /// @inheritdoc IPausePoolHelper
    function addPools(address[] calldata newPools) external authenticate {
        uint256 length = newPools.length;

        for (uint256 i = 0; i < length; i++) {
            address pool = newPools[i];
            if (_pausablePools.add(pool) == false) {
                revert PoolAlreadyInPausableSet(pool);
            }

            emit PoolAddedToPausableSet(pool);
        }
    }

    /// @inheritdoc IPausePoolHelper
    function removePools(address[] memory pools) public authenticate {
        uint256 length = pools.length;
        for (uint256 i = 0; i < length; i++) {
            address pool = pools[i];
            if (_pausablePools.remove(pool) == false) {
                revert PoolNotInPausableSet(pool);
            }

            emit PoolRemovedFromPausableSet(pool);
        }
    }

    /// @inheritdoc IPausePoolHelper
    function pausePools(address[] memory pools) public authenticate {
        uint256 length = pools.length;
        for (uint256 i = 0; i < length; i++) {
            address pool = pools[i];
            if (_pausablePools.contains(pool) == false) {
                revert PoolNotInPausableSet(pool);
            }

            getVault().pausePool(pool);
        }
    }

    /***************************************************************************
                                    Getters                                
    ***************************************************************************/

    /// @inheritdoc IPausePoolHelper
    function getPoolsCount() external view returns (uint256) {
        return _pausablePools.length();
    }

    /// @inheritdoc IPausePoolHelper
    function hasPool(address pool) external view returns (bool) {
        return _pausablePools.contains(pool);
    }

    /// @inheritdoc IPausePoolHelper
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
