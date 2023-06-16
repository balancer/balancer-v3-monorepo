// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "../solidity-utils/openzeppelin/IERC20.sol";

/**
 * @dev Full external interface for the Vault core contract - no external or public methods exist in the contract that
 * don't override one of these declarations.
 */

interface IVault {
    // Generalities about the Vault:
    //
    // - Whenever documentation refers to 'tokens', it strictly refers to ERC20-compliant token contracts.
    // The only deviation from the ERC20 standard that is supported is functions not returning a boolean value:
    // in these scenarios, a non-reverting call is assumed to be successful.
    //
    // - All non-view functions in the Vault are non-reentrant: calling them while another one is mid-execution (e.g.
    // while execution control is transferred to a token contract during a swap) will result in a revert. View
    // functions can be called in a re-reentrant way, but doing so might cause them to return inconsistent results.
    // Contracts calling view functions in the Vault must make sure the Vault has not already been entered.
    //
    // - View functions revert if referring to either unregistered Pools, or unregistered tokens for registered Pools.

    /**
     * @dev Registers the caller account as a Pool. Must be called by the Pool's contract. Pools and tokens cannot
     * be deregistered.
     *
     * Pools can only interact with tokens they have registered. Users join a Pool by transferring registered tokens,
     * exit by receiving registered tokens, and can only swap registered tokens.
     *
     * Emits a `PoolRegistered` event.
     */
    function registerPool(IERC20[] memory tokens) external;

    /**
     * @dev Returns whether or not an address corresponds to a registered pool.
     * @param poolAddress - address of the suspected pool.
     */
    function isRegisteredPool(address poolAddress) external view returns (bool);

    /**
     * @dev Emitted when a Pool is registered by calling `registerPool`.
     * @param poolAddress - address of the pool being registered.
     */
    event PoolRegistered(address indexed poolAddress, IERC20[] tokens);

    /**
     * @dev Error indicating that a pool has already been registered.
     * @param poolAddress - the address of the duplicate pool.
     */
    error PoolAlreadyRegistered(address poolAddress);

    /**
     * @dev Error indicating that a referenced pool has not been registered.
     * @param poolAddress - the address of the unregistered pool.
     */
    error PoolNotRegistered(address poolAddress);

    /**
     * @dev Error indicating an attempt to register an invalid token.
     */
    error InvalidToken();

    /**
     * @dev Error indicating a token was already registered (i.e., a duplicate). 
     */
    error TokenAlreadyRegistered(IERC20 tokenAddress);

    /**
     * @dev Returns a Pool's registered tokens and balances.
     *
     * The order of the `tokens` and `balances` arrays is the same order that will be used in `joinPool`, `exitPool`,
     * as well as in all Pool hooks (where applicable).
     */
    function getPoolTokens(address poolAddress) external view returns (IERC20[] memory tokens, uint256[] memory balances);
}
