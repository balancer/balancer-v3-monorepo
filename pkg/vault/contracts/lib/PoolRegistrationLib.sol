// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";
import {
    IVault,
    PoolConfig,
    PoolCallbacks,
    LiquidityManagement,
    PoolData,
    Rounding
} from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { EnumerableMap } from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/EnumerableMap.sol";

import { PoolConfigBits, PoolConfigLib } from "./PoolConfigLib.sol";

library PoolRegistrationLib {
    using EnumerableMap for EnumerableMap.IERC20ToUint256Map;
    using SafeCast for *;
    using PoolConfigLib for PoolConfig;

    /**
     * @dev A pool has already been registered. `registerPool` may only be called once.
     * @param pool The already registered pool
     */
    error PoolAlreadyRegistered(address pool);

    /// @dev The token count is below the minimum allowed.
    error MinTokens();

    /// @dev The token count is above the maximum allowed.
    error MaxTokens();

    /// @dev Invalid tokens (e.g., zero) cannot be registered.
    error InvalidToken();

    /**
     * @dev A token was already registered (i.e., it is a duplicate in the pool).
     * @param token The duplicate token
     */
    error TokenAlreadyRegistered(IERC20 token);

    /**
     * @notice A Pool was registered by calling `registerPool`.
     * @param pool The pool being registered
     * @param factory The factory creating the pool
     * @param tokens The pool's tokens
     * @param rateProviders The pool's rate providers (or zero)
     * @param pauseWindowEndTime The pool's pause window end time
     * @param pauseManager The pool's external pause manager (or 0 for governance)
     * @param liquidityManagement Supported liquidity management callback flags
     */
    event PoolRegistered(
        address indexed pool,
        address indexed factory,
        IERC20[] tokens,
        IRateProvider[] rateProviders,
        uint256 pauseWindowEndTime,
        address pauseManager,
        PoolCallbacks callbacks,
        LiquidityManagement liquidityManagement
    );

    // Pools can have two, three, or four tokens.
    uint256 internal constant MIN_TOKENS = 2;
    // This maximum token count is also hard-coded in `PoolConfigLib`.
    uint256 internal constant MAX_TOKENS = 4;

    /**
     * @dev The function will register the pool, setting its tokens with an initial balance of zero.
     * The function also checks for valid token addresses and ensures that the pool and tokens aren't
     * already registered.
     *
     * Emits a `PoolRegistered` event upon successful registration.
     */
    function registerPool(
        address pool,
        EnumerableMap.IERC20ToUint256Map storage poolTokenBalances,
        mapping(address => address) storage poolPauseManagers,
        mapping(address => PoolConfigBits) storage poolConfig,
        mapping(IERC20 => IRateProvider) storage poolRateProviders,
        IERC20[] memory tokens,
        IRateProvider[] memory rateProviders,
        uint256 pauseWindowEndTime,
        address pauseManager,
        PoolCallbacks memory callbackConfig,
        LiquidityManagement memory liquidityManagement
    ) external {
        // Ensure the pool isn't already registered
        if (_isPoolRegistered(poolConfig, pool)) {
            revert PoolAlreadyRegistered(pool);
        }

        if (tokens.length < MIN_TOKENS) {
            revert MinTokens();
        }
        if (tokens.length > MAX_TOKENS) {
            revert MaxTokens();
        }

        uint8[] memory tokenDecimalDiffs = new uint8[](tokens.length);

        for (uint256 i = 0; i < tokens.length; ++i) {
            IERC20 token = tokens[i];

            // Ensure that the token address is valid
            if (token == IERC20(address(0))) {
                revert InvalidToken();
            }

            // Register the token with an initial balance of zero.
            // Note: EnumerableMaps require an explicit initial value when creating a key-value pair.
            // Ensure the token isn't already registered for the pool
            if (!poolTokenBalances.set(token, 0)) {
                revert TokenAlreadyRegistered(token);
            }

            tokenDecimalDiffs[i] = uint8(18) - IERC20Metadata(address(token)).decimals();
            poolRateProviders[token] = rateProviders[i];
        }

        // Store the pause manager. A zero address means default to the authorizer.
        poolPauseManagers[pool] = pauseManager;

        // Store config and mark the pool as registered
        PoolConfig memory config = PoolConfigLib.toPoolConfig(poolConfig[pool]);

        config.isPoolRegistered = true;
        config.callbacks = callbackConfig;
        config.liquidityManagement = liquidityManagement;
        config.tokenDecimalDiffs = PoolConfigLib.toTokenDecimalDiffs(tokenDecimalDiffs);
        config.pauseWindowEndTime = pauseWindowEndTime.toUint32();
        poolConfig[pool] = config.fromPoolConfig();

        // Emit an event to log the pool registration (pass msg.sender as the factory argument)
        emit PoolRegistered(
            pool,
            msg.sender,
            tokens,
            rateProviders,
            pauseWindowEndTime,
            pauseManager,
            callbackConfig,
            liquidityManagement
        );
    }

    /// @dev See `isPoolRegistered`
    function _isPoolRegistered(mapping(address => PoolConfigBits) storage poolConfig, address pool) internal view returns (bool) {
        return poolConfig[pool].isPoolRegistered();
    }
}