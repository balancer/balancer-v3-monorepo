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

    // Pool -> (token -> balance): Vault tokens allocated to this pool
    mapping(address => EnumerableMap.IERC20ToUint256Map) private _poolTokenBalances;

    /**
     * @dev Error indicating an attempt to register an invalid token.
     */
    error InvalidToken();

    /**
     * @dev Error indicating a token was already registered (i.e., a duplicate).
     */
    error TokenAlreadyRegistered(IERC20 tokenAddress);

    /**
     * @dev Reverts unless `poolAddress` corresponds to a registered Pool.
     */
    modifier withRegisteredPool(address poolAddress) {
        _ensureRegisteredPool(poolAddress);
        _;
    }

    /**
     * @dev Reverts unless `poolAddress` corresponds to a registered Pool.
     */
    function _ensureRegisteredPool(address poolAddress) internal view {
        if (!isRegisteredPool(poolAddress)) {
            revert PoolNotRegistered(poolAddress);
        }
    }

    /// @inheritdoc IVault
    function registerPool(IERC20[] memory tokens) external override nonReentrant whenNotPaused {
        address poolAddress = msg.sender;

        if (isRegisteredPool(poolAddress)) {
            revert PoolAlreadyRegistered(poolAddress);
        }

        EnumerableMap.IERC20ToUint256Map storage poolTokenBalances = _poolTokenBalances[poolAddress];

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

        _isPoolRegistered[poolAddress] = true;
        emit PoolRegistered(poolAddress, tokens);
    }

    /// @inheritdoc IVault
    function isRegisteredPool(address poolAddress) public view returns (bool) {
        return _isPoolRegistered[poolAddress];
    }

    /// @inheritdoc IVault
    function getPoolTokens(
        address poolAddress
    )
        external
        view
        override
        withRegisteredPool(poolAddress)
        returns (IERC20[] memory tokens, uint256[] memory balances)
    {
        EnumerableMap.IERC20ToUint256Map storage poolTokenBalances = _poolTokenBalances[poolAddress];

        tokens = new IERC20[](poolTokenBalances.length());
        balances = new uint256[](tokens.length);

        for (uint256 i = 0; i < tokens.length; ++i) {
            // Because the iteration is bounded by `tokens.length`, which matches the EnumerableMap's length, we can use
            // `unchecked_at` as we know `i` is a valid token index, saving storage reads.
            (tokens[i], balances[i]) = poolTokenBalances.unchecked_at(i);
        }
    }
}
