// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IVaultEvents } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultEvents.sol";
import { Authentication } from "@balancer-labs/v3-solidity-utils/contracts/helpers/Authentication.sol";
import { EnumerableMap } from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/EnumerableMap.sol";
import { PoolConfigBits, PoolConfigLib } from "./lib/PoolConfigLib.sol";
import { VaultStorage } from "./VaultStorage.sol";

/**
 * @dev Storage layout for Vault. This contract has no code except for common utilities in the inheritance chain
 * that require storage to work and will be required in both the main Vault and its extension.
 */
abstract contract VaultCommon is IVaultEvents, IVaultErrors, VaultStorage, Authentication, ReentrancyGuard {
    /*******************************************************************************
                                    Vault Pausing
    *******************************************************************************/

    /// @dev Modifier to make a function callable only when the Vault is not paused.
    modifier whenVaultNotPaused() {
        _ensureVaultNotPaused();
        _;
    }

    /// @dev Reverts if the Vault is paused.
    function _ensureVaultNotPaused() internal view {
        if (_isVaultPaused()) {
            revert VaultPaused();
        }
    }

    /**
     * @dev For gas efficiency, storage is only read before `_vaultBufferPeriodEndTime`. Once we're past that
     * timestamp, the expression short-circuits false, and the Vault is permanently unpaused.
     */
    function _isVaultPaused() internal view returns (bool) {
        return block.timestamp <= _vaultBufferPeriodEndTime && _vaultPaused;
    }

    /*******************************************************************************
                                    Vault Pausing
    *******************************************************************************/

    /// @dev Modifier to make a function callable only when the Vault and Pool are not paused.
    modifier whenPoolNotPaused(address pool) {
        _ensureVaultNotPaused();
        _ensurePoolNotPaused(pool);
        _;
    }

    /**
     * @dev Reverts if the pool is paused.
     * @param pool The pool
     */
    function _ensurePoolNotPaused(address pool) internal view {
        if (_isPoolPaused(pool)) {
            revert PoolPaused(pool);
        }
    }

    /// @dev Check both the flag and timestamp to determine whether the pool is paused.
    function _isPoolPaused(address pool) internal view returns (bool) {
        (bool paused, ) = _getPoolPausedState(pool);

        return paused;
    }

    /// @dev Lowest level routine that plucks only the minimum necessary parts from storage.
    function _getPoolPausedState(address pool) internal view returns (bool, uint256) {
        (bool pauseBit, uint256 pauseWindowEndTime) = PoolConfigLib.getPoolPausedState(_poolConfig[pool]);

        // Use the Vault's buffer period.
        return (pauseBit && block.timestamp <= pauseWindowEndTime + _vaultBufferPeriodDuration, pauseWindowEndTime);
    }

    /*******************************************************************************
                            Pool Registration and Initialization
    *******************************************************************************/

    /// @dev Reverts unless `pool` corresponds to a registered Pool.
    modifier withRegisteredPool(address pool) {
        _ensureRegisteredPool(pool);
        _;
    }

    /// @dev Reverts unless `pool` corresponds to a registered Pool.
    function _ensureRegisteredPool(address pool) internal view {
        if (!_isPoolRegistered(pool)) {
            revert PoolNotRegistered(pool);
        }
    }

    /// @dev See `isPoolRegistered`
    function _isPoolRegistered(address pool) internal view returns (bool) {
        return _poolConfig[pool].isPoolRegistered();
    }

    /*******************************************************************************
                                    Recovery Mode
    *******************************************************************************/

    /**
     * @dev Place on functions that may only be called when the associated pool is in recovery mode.
     * @param pool The pool
     */
    modifier onlyInRecoveryMode(address pool) {
        _ensurePoolInRecoveryMode(pool);
        _;
    }

    /**
     * @dev Reverts if the pool is not in recovery mode.
     * @param pool The pool
     */
    function _ensurePoolInRecoveryMode(address pool) internal view {
        if (!_isPoolInRecoveryMode(pool)) {
            revert PoolNotInRecoveryMode(pool);
        }
    }

    /**
     * @notice Checks whether a pool is in recovery mode.
     * @param pool Address of the pool to check
     * @return True if the pool is initialized, false otherwise
     */
    function _isPoolInRecoveryMode(address pool) internal view returns (bool) {
        return _poolConfig[pool].isPoolInRecoveryMode();
    }
}
