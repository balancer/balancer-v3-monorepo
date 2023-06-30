// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";

import "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/EnumerableMap.sol";

/**
 * @dev Maintains a registry of pool addresses, which allows users to verify that a pool is valid and present in
 * the Vault. It also defines useful modifiers nd helper functions for ensuring correct behavior when working
 * with Pools.
 */
abstract contract PoolRegistry is IVaultErrors {
    using EnumerableMap for EnumerableMap.IERC20ToUint256Map;

    // Registry of pool addresses.
    mapping(address => bool) private _isPoolRegistered;

    // Pool -> (token -> balance): Vault tokens allocated to this pool
    mapping(address => EnumerableMap.IERC20ToUint256Map) private _poolTokenBalances;

    /**
     * @dev Emitted when a Pool is registered by calling `registerPool`.
     */
    event PoolRegistered(address indexed pool, address indexed factory, IERC20[] tokens);

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
        if (!_isRegisteredPool(pool)) {
            revert PoolNotRegistered(pool);
        }
    }

    function _registerPool(address factory, IERC20[] memory tokens) internal {
        address pool = msg.sender;

        if (_isRegisteredPool(pool)) {
            revert PoolAlreadyRegistered(pool);
        }

        EnumerableMap.IERC20ToUint256Map storage poolTokenBalances = _poolTokenBalances[pool];

        for (uint256 i = 0; i < tokens.length; ++i) {
            IERC20 token = tokens[i];

            if (token == IERC20(address(0))) {
                revert InvalidToken();
            }

            // EnumerableMaps require an explicit initial value when creating a key-value pair: we use zero, the same
            // value that is found in uninitialized storage, which corresponds to an empty balance.
            bool added = poolTokenBalances.set(tokens[i], 0);
            if (!added) {
                revert TokenAlreadyRegistered(tokens[i]);
            }
        }

        _isPoolRegistered[pool] = true;
        emit PoolRegistered(pool, factory, tokens);
    }

    function _isRegisteredPool(address pool) internal view returns (bool) {
        return _isPoolRegistered[pool];
    }

    function _getPoolTokens(address pool) internal view returns (IERC20[] memory tokens, uint256[] memory balances) {
        EnumerableMap.IERC20ToUint256Map storage poolTokenBalances = _poolTokenBalances[pool];

        tokens = new IERC20[](poolTokenBalances.length());
        balances = new uint256[](tokens.length);

        for (uint256 i = 0; i < tokens.length; ++i) {
            // Because the iteration is bounded by `tokens.length`, which matches the EnumerableMap's length, we can use
            // `unchecked_at` as we know `i` is a valid token index, saving storage reads.
            (tokens[i], balances[i]) = poolTokenBalances.unchecked_at(i);
        }
    }
}
