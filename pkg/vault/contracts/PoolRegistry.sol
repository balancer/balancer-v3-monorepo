// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/ReentrancyGuard.sol";
import "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/EnumerableMap.sol";
import "@balancer-labs/v3-solidity-utils/contracts/helpers/TemporarilyPausable.sol";

/**
 * @dev Maintains the Pool ID data structure, implements Pool ID creation and registration, and defines useful modifiers
 * and helper functions for ensuring correct behavior when working with Pools.
 */
abstract contract PoolRegistry is IVault, ReentrancyGuard, TemporarilyPausable {
    using EnumerableMap for EnumerableMap.IERC20ToUint256Map;

    // Registry of pool addresses.
    mapping(address => bool) private _isPoolRegistered;

    mapping(address => EnumerableMap.IERC20ToUint256Map) internal _poolBalances;

    /**
     * @dev Error indicating an attempt to register an invalid token.
     */
    error InvalidToken();

    /**
     * @dev Error indicating a token was already registered (i.e., a duplicate).
     */
    error TokenAlreadyRegistered(IERC20 tokenAddress);

    /**
     * @dev Reverts unless `pool` corresponds to a registered Pool.
     */
    modifier withRegisteredPool(address pool) {
        _ensureRegisteredPool(pool);
        _;
    }

    /**
     * @dev Reverts unless `pool` corresponds to a registered Pool.
     */
    function _ensureRegisteredPool(address pool) internal view {
        if (!isRegisteredPool(pool)) {
            revert PoolNotRegistered(pool);
        }
    }

    /// @inheritdoc IVault
    function registerPool(address factory, IERC20[] memory tokens) external override nonReentrant whenNotPaused {
        address pool = msg.sender;

        if (isRegisteredPool(pool)) {
            revert PoolAlreadyRegistered(pool);
        }

        EnumerableMap.IERC20ToUint256Map storage poolBalances = _poolBalances[pool];

        for (uint256 i = 0; i < tokens.length; ++i) {
            IERC20 token = tokens[i];

            if (token == IERC20(address(0))) {
                revert InvalidToken();
            }

            // EnumerableMaps require an explicit initial value when creating a key-value pair: we use zero, the same
            // value that is found in uninitialized storage, which corresponds to an empty balance.
            bool added = poolBalances.set(tokens[i], 0);
            if (!added) {
                revert TokenAlreadyRegistered(tokens[i]);
            }
        }

        _isPoolRegistered[pool] = true;
        emit PoolRegistered(pool, factory, tokens);
    }

    /// @inheritdoc IVault
    function isRegisteredPool(address pool) public view returns (bool) {
        return _isPoolRegistered[pool];
    }

    /// @inheritdoc IVault
    function getPoolTokens(
        address pool
    ) external view override withRegisteredPool(pool) returns (IERC20[] memory tokens, uint256[] memory balances) {
        EnumerableMap.IERC20ToUint256Map storage poolBalances = _poolBalances[pool];

        tokens = new IERC20[](poolBalances.length());
        balances = new uint256[](tokens.length);

        for (uint256 i = 0; i < tokens.length; ++i) {
            // Because the iteration is bounded by `tokens.length`, which matches the EnumerableMap's length, we can use
            // `unchecked_at` as we know `i` is a valid token index, saving storage reads.
            (tokens[i], balances[i]) = poolBalances.unchecked_at(i);
        }
    }
}
