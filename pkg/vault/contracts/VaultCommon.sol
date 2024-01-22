// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IVaultEvents } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultEvents.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { EnumerableMap } from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/EnumerableMap.sol";
import { PoolConfigBits, PoolConfigLib } from "./lib/PoolConfigLib.sol";
import { VaultStorage } from "./VaultStorage.sol";
import { ERC20MultiToken } from "./token/ERC20MultiToken.sol";

/**
 * @dev Storage layout for Vault. This contract has no code except for common utilities in the inheritance chain
 * that require storage to work and will be required in both the main Vault and its extension.
 */
abstract contract VaultCommon is IVaultEvents, IVaultErrors, VaultStorage, ReentrancyGuard, ERC20MultiToken {
    using EnumerableMap for EnumerableMap.IERC20ToUint256Map;

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

    /// @dev Reverts unless `pool` corresponds to an initialized Pool.
    function _ensureInitializedPool(address pool) internal view {
        if (!_isPoolInitialized(pool)) {
            revert PoolNotInitialized(pool);
        }
    }

    /// @dev See `isPoolInitialized`
    function _isPoolInitialized(address pool) internal view returns (bool) {
        return _poolConfig[pool].isPoolInitialized();
    }

    /*******************************************************************************
                                    Pool Information
    *******************************************************************************/

    /**
     * @notice Fetches the tokens and their corresponding balances for a given pool.
     * @dev Utilizes an enumerable map to obtain pool token balances.
     * The function is structured to minimize storage reads by leveraging the `unchecked_at` method.
     *
     * @param pool The address of the pool for which tokens and balances are to be fetched.
     * @return tokens An array of token addresses.
     */
    function _getPoolTokens(address pool) internal view returns (IERC20[] memory tokens) {
        // Retrieve the mapping of tokens and their balances for the specified pool.
        EnumerableMap.IERC20ToUint256Map storage poolTokenBalances = _poolTokenBalances[pool];

        // Initialize arrays to store tokens based on the number of tokens in the pool.
        tokens = new IERC20[](poolTokenBalances.length());

        for (uint256 i = 0; i < tokens.length; ++i) {
            // Because the iteration is bounded by `tokens.length`, which matches the EnumerableMap's length,
            // we can safely use `unchecked_at`. This ensures that `i` is a valid token index and minimizes
            // storage reads.
            (tokens[i], ) = poolTokenBalances.unchecked_at(i);
        }
    }

    function _getPoolTokenInfo(
        address pool
    )
        internal
        view
        returns (
            IERC20[] memory tokens,
            TokenType[] memory tokenTypes,
            uint256[] memory balancesRaw,
            uint256[] memory decimalScalingFactors,
            IRateProvider[] memory rateProviders,
            PoolConfig memory poolConfig
        )
    {
        EnumerableMap.IERC20ToUint256Map storage poolTokenBalances = _poolTokenBalances[pool];
        mapping(IERC20 => TokenConfig) storage poolTokenConfig = _poolTokenConfig[pool];

        uint256 numTokens = poolTokenBalances.length();
        poolConfig = _poolConfig[pool].toPoolConfig();

        tokens = new IERC20[](numTokens);
        tokenTypes = new TokenType[](numTokens);
        balancesRaw = new uint256[](numTokens);
        rateProviders = new IRateProvider[](numTokens);
        decimalScalingFactors = PoolConfigLib.getDecimalScalingFactors(poolConfig, numTokens);
        IERC20 token;

        for (uint256 i = 0; i < numTokens; i++) {
            (token, balancesRaw[i]) = poolTokenBalances.unchecked_at(i);
            tokens[i] = token;
            rateProviders[i] = poolTokenConfig[token].rateProvider;
            tokenTypes[i] = poolTokenConfig[token].tokenType;
        }
    }

    /**
     * @dev Called by the external `getPoolTokenRates` function, and internally during pool operations,
     * this will make external calls for tokens that have rate providers.
     */
    function _getPoolTokenRates(address pool) internal view returns (uint256[] memory tokenRates) {
        // Retrieve the mapping of tokens for the specified pool.
        EnumerableMap.IERC20ToUint256Map storage poolTokenBalances = _poolTokenBalances[pool];
        mapping(IERC20 => TokenConfig) storage poolTokenConfig = _poolTokenConfig[pool];

        // Initialize arrays to store tokens based on the number of tokens in the pool.
        tokenRates = new uint256[](poolTokenBalances.length());
        IERC20 token;

        for (uint256 i = 0; i < tokenRates.length; ++i) {
            // Because the iteration is bounded by `tokenRates.length`, which matches the EnumerableMap's
            // length, we can safely use `unchecked_at`. This ensures that `i` is a valid token index and minimizes
            // storage reads.
            (token, ) = poolTokenBalances.unchecked_at(i);
            TokenType tokenType = poolTokenConfig[token].tokenType;

            if (tokenType == TokenType.STANDARD) {
                tokenRates[i] = FixedPoint.ONE;
            } else if (tokenType == TokenType.WITH_RATE) {
                tokenRates[i] = poolTokenConfig[token].rateProvider.getRate();
            } else {
                // TODO implement ERC4626 at a later stage.
                revert InvalidTokenConfiguration();
            }
        }
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
