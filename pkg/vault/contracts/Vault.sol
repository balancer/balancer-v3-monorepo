// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/ReentrancyGuard.sol";
import "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/EnumerableMap.sol";
import "@balancer-labs/v3-solidity-utils/contracts/helpers/TemporarilyPausable.sol";

contract Vault is IVault, TemporarilyPausable, ReentrancyGuard {
    using EnumerableMap for EnumerableMap.IERC20ToUint256MapEntry;

    // State variables

    mapping(address => bool) private _isPoolRegistered;

    // Pool -> (token -> balance)
    mapping(address => EnumerableMap.IERC20ToUint256MapEntry) internal _poolBalances;

    // Modifiers

    /**
     * @dev Reverts unless `poolId` corresponds to a registered Pool.
     */
    modifier withRegisteredPool(address poolAddress) {
        _ensureRegisteredPool(poolAddress);
        _;
    }

    // Public Functions

    /// @inheritdoc IVault
    function registerPool(IERC20[] memory tokens) external nonReentrant whenNotPaused override {
        address poolAddress = msg.sender;

        if (isRegisteredPool(poolAddress)) {
            revert PoolAlreadyRegistered(poolAddress);
        }

        EnumerableMap.IERC20ToUint256MapEntry storage poolBalances = _poolBalances[poolAddress];

        for (uint256 i = 0; i < tokens.length; ++i) {
            IERC20 token = tokens[i];

            if (token == IERC20(0)) {
                revert InvalidToken();
            }

            // EnumerableMaps require an explicit initial value when creating a key-value pair: we use zero, the same
            // value that is found in uninitialized storage, which corresponds to an empty balance.
            bool added = poolBalances.set(tokens[i], 0);
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
    function getPoolTokens(address poolAddress) external view withRegisteredPool(poolAddress) override returns (IERC20[] memory tokens, uint256[] memory balances) {
        EnumerableMap.IERC20ToUint256MapEntry storage poolBalances = _poolBalances[poolAddress];

        tokens = new IERC20[](poolBalances.length());
        balances = new bytes32[](tokens.length);

        for (uint256 i = 0; i < tokens.length; ++i) {
            // Because the iteration is bounded by `tokens.length`, which matches the EnumerableMap's length, we can use
            // `unchecked_at` as we know `i` is a valid token index, saving storage reads.
            (tokens[i], balances[i]) = poolBalances.unchecked_at(i);
        }
    }

    // Internal functions

    /**
     * @dev Reverts unless `poolAddress` corresponds to a registered Pool.
     */
    function _ensureRegisteredPool(address poolAddress) internal view {
        if (!isRegisteredPool(poolAddress)) {
            revert InvalidPoolAddress(poolAddress);
        }
    }
}