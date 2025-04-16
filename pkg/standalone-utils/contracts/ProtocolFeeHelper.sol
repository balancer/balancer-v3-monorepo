// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import { IProtocolFeeHelper } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IProtocolFeeHelper.sol";
import { IProtocolFeeController } from "@balancer-labs/v3-interfaces/contracts/vault/IProtocolFeeController.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { SingletonAuthentication } from "@balancer-labs/v3-vault/contracts/SingletonAuthentication.sol";

contract ProtocolFeeHelper is IProtocolFeeHelper, SingletonAuthentication {
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet private _pools;

    modifier withKnownPool(address pool) {
        _ensureKnownPool(pool);
        _;
    }

    constructor(IVault vault) SingletonAuthentication(vault) {
        // solhint-disable-previous-line no-empty-blocks
    }

    /***************************************************************************
                                    Manage Pools
    ***************************************************************************/

    /// @inheritdoc IProtocolFeeHelper
    function addPools(address[] calldata newPools) external authenticate {
        uint256 length = newPools.length;
        IVault vault = getVault();

        for (uint256 i = 0; i < length; i++) {
            address pool = newPools[i];

            // Ensure the address is a valid pool.
            if (vault.isPoolRegistered(pool) == false) {
                revert IVaultErrors.PoolNotRegistered(pool);
            }

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
            _ensureKnownPool(pool);

            _pools.remove(pool);

            emit PoolRemovedFromProtocolFeeSet(pool);
        }
    }

    /// @inheritdoc IProtocolFeeHelper
    function setProtocolSwapFeePercentage(
        address pool,
        uint256 newProtocolSwapFeePercentage
    ) external withKnownPool(pool) authenticate {
        _getProtocolFeeController().setProtocolSwapFeePercentage(pool, newProtocolSwapFeePercentage);
    }

    /// @inheritdoc IProtocolFeeHelper
    function setProtocolYieldFeePercentage(
        address pool,
        uint256 newProtocolYieldFeePercentage
    ) external withKnownPool(pool) authenticate {
        _getProtocolFeeController().setProtocolYieldFeePercentage(pool, newProtocolYieldFeePercentage);
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

    /***************************************************************************
                                Internal functions                                
    ***************************************************************************/

    // The protocol fee controller is upgradeable in the Vault, so we must fetch it every time.
    function _getProtocolFeeController() internal view returns (IProtocolFeeController) {
        return getVault().getProtocolFeeController();
    }

    function _ensureKnownPool(address pool) internal view {
        if (_pools.contains(pool) == false) {
            revert PoolNotInProtocolFeeSet(pool);
        }
    }
}
