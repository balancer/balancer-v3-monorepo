// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IVaultErrors {
    /**
     * @dev Error indicating that a pool has already been registered.
     */
    error PoolAlreadyRegistered(address pool);

    /**
     * @dev Error indicating that a referenced pool has not been registered.
     */
    error PoolNotRegistered(address pool);

    /**
     * @dev Error indicating an attempt to register an invalid token.
     */
    error InvalidToken();

    /**
     * @dev Error indicating a token was already registered (i.e., a duplicate).
     */
    error TokenAlreadyRegistered(IERC20 tokenAddress);

    /**
     * @dev Error indicating the sender is not the Vault (e.g., someone is trying to call a permissioned function).
     */
    error SenderIsNotVault(address sender);

    /**
     * @dev
     */
    error TokensMismatch(address tokenA, address tokenB);

    /**
     * @dev
     */
    error PoolHasNoTokens(address pool);

    /**
     * @dev
     */
    error JoinAboveMax();

    /**
     * @dev
     */
    error InvalidEthInternalBalance();

    /**
     * @dev
     */
    error InsufficientEth();
}
