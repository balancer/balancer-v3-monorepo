// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { IProtocolFeeHelper } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IProtocolFeeHelper.sol";
import { SingletonAuthentication } from "@balancer-labs/v3-vault/contracts/SingletonAuthentication.sol";

contract ProtocolFeeHelper is IProtocolFeeHelper, SingletonAuthentication {
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet private _pools;

    constructor(IVault vault) SingletonAuthentication(vault) {
        // solhint-disable-previous-line no-empty-blocks
    }

    /***************************************************************************
                                    Manage Pools
    ***************************************************************************/

    /// @inheritdoc IProtocolFeeHelper
    function addPools(address[] calldata newPools) external authenticate {
        uint256 length = newPools.length;

        for (uint256 i = 0; i < length; i++) {
            address pool = newPools[i];
            if (_pools.add(pool) == false) {
                revert PoolAlreadyInProtocolFeeSet(pool);
            }

            emit PoolAddedToProtocolFeeSet(pool);
        }
    }

    /// @inheritdoc IProtocolFeeHelper
    function removePools(address[] memory pools) public authenticate {
        uint256 length = pools.length;
        for (uint256 i = 0; i < length; i++) {
            address pool = pools[i];
            if (_pools.remove(pool) == false) {
                revert PoolNotInProtocolFeeSet(pool);
            }

            emit PoolRemovedFromProtocolFeeSet(pool);
        }
    }

    /// @inheritdoc IProtocolFeeHelper
    function setProtocolSwapFeePercentage(address pool, uint256 protocolSwapFee) external authenticate {
        if (_pools.contains(pool) == false) {
            revert PoolNotInProtocolFeeSet(pool);
        }

        getVault().getProtocolFeeController().setProtocolSwapFeePercentage(pool, protocolSwapFee);
    }

    /// @inheritdoc IProtocolFeeHelper
    function setProtocolYieldFeePercentage(address pool, uint256 protocolYieldFee) external authenticate {
        if (_pools.contains(pool) == false) {
            revert PoolNotInProtocolFeeSet(pool);
        }

        getVault().getProtocolFeeController().setProtocolYieldFeePercentage(pool, protocolYieldFee);
    }

    /***************************************************************************
                                    Getters                                
    ***************************************************************************/

    /// @inheritdoc IProtocolFeeHelper
    function getPoolCount() external view returns (uint256) {
        return _pools.length();
    }

    /// @inheritdoc IProtocolFeeHelper
    function hasPool(address pool) external view returns (bool) {
        return _pools.contains(pool);
    }

    /// @inheritdoc IProtocolFeeHelper
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
}
