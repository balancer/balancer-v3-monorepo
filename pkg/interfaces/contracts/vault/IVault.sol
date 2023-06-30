// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../solidity-utils/misc/IWETH.sol";

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
     * @dev Expose the WETH address (for wrapping and unwrapping native ETH).
     */
    // solhint-disable-next-line func-name-mixedcase
    function WETH() external view returns (IWETH);

    /**
     * @dev Registers the caller account as a Pool. Must be called by the Pool's contract. Pools and tokens cannot
     * be deregistered.
     *
     * Pools can only interact with tokens they have registered. Users join a Pool by transferring registered tokens,
     * exit by receiving registered tokens, and can only swap registered tokens.
     *
     * Emits a `PoolRegistered` event.
     * @param factory Address of the factory that deployed this pool
     * @param tokens Tokens registered with this pool
     */
    function registerPool(address factory, IERC20[] memory tokens) external;

    /**
     * @dev Returns whether or not an address corresponds to a registered pool.
     */
    function isRegisteredPool(address pool) external view returns (bool);

    /**
     * @dev Returns a Pool's registered tokens and balances.
     *
     * The order of the `tokens` and `balances` arrays is the same order that will be used in `joinPool`, `exitPool`,
     * as well as in all Pool hooks (where applicable).
     */
    function getPoolTokens(address pool) external view returns (IERC20[] memory tokens, uint256[] memory balances);

    /**
     * @dev Returns the total supply of a BPT token.
     */
    function totalSupply(address poolToken) external view returns (uint256);

    /**
     * @dev Returns an account's balance of a BPT token.
     */
    function balanceOf(address poolToken, address account) external view returns (uint256);

    /**
     * @dev Permissioned function to transfer a BPT token. Can only be called from a registered pool.
     */
    function transfer(address owner, address to, uint256 amount) external returns (bool);

    /**
     * @dev Permissioned function to transferFrom a BPT token. Can only be called from a registered pool.
     */
    function transferFrom(address spender, address from, address to, uint256 amount) external returns (bool);

    /**
     * @dev Returns an owner's BPT allowance for a given spender.
     */
    function allowance(address poolToken, address owner, address spender) external view returns (uint256);

    /**
     * @dev Permissioned function to set a sender's BPT allowance for a given spender. Can only be called
     * from a registered pool.
     */
    function approve(address sender, address spender, uint256 amount) external returns (bool);
}
