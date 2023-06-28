// SPDX-License-Identifier: MIT

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
     * @dev Emitted when a Pool is registered by calling `registerPool`.
     */
    event PoolRegistered(address indexed pool, address indexed factory, IERC20[] tokens);

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
     * @dev Expose the WETH address (for wrapping and unwrapping native ETH).
     */
    // solhint-disable-next-line func-name-mixedcase
    function WETH() external view returns (IWETH);

    /***********************/
    /*  Pool Registration  */
    /***********************/

    /**
     * @dev Registers the caller account as a Pool. Must be called by the Pool's contract. Pools and tokens cannot
     * be deregistered.
     *
     * Pools can only interact with tokens they have registered. Users join a Pool by transferring registered tokens,
     * exit by receiving registered tokens, and can only swap registered tokens.
     *
     * Emits a `PoolRegistered` event.
     * @param factory - address of the factory that deployed this pool
     * @param tokens - tokens registered with this pool
     */
    function registerPool(address factory, IERC20[] memory tokens) external;

    /**
     * @dev Returns whether or not an address corresponds to a registered pool.
     * @param pool - address of the suspected pool.
     */
    function isRegisteredPool(address pool) external view returns (bool);

    /**
     * @dev Returns a Pool's registered tokens and balances.
     *
     * The order of the `tokens` and `balances` arrays is the same order that will be used in `joinPool`, `exitPool`,
     * as well as in all Pool hooks (where applicable).
     */
    function getPoolTokens(address pool) external view returns (IERC20[] memory tokens, uint256[] memory balances);

    /***************************/
    /*  Balancer ERC20 tokens  */
    /***************************/

    /**
     * @dev Returns the total supply of a BPT token.
     */
    function totalSupply(address poolToken) external view returns (uint256);

    /**
     * @dev Returns an account's balance of a BPT token.
     */
    function balanceOf(address poolToken, address account) external view returns (uint256);

    /**
     * @dev Permissioned function to transfer a BPT token.
     */
    function transfer(
        address poolToken,
        address owner,
        address to,
        uint256 amount
    ) external returns (bool);

    /**
     * @dev Permissioned function to transferFrom a BPT token.
     */
    function transferFrom(
        address poolToken,
        address spender,
        address from,
        address to,
        uint256 amount
    ) external returns (bool);

    /**
     * @dev Returns an owner's BPT allowance for a given spender.
     */
    function allowance(
        address poolToken,
        address owner,
        address spender
    ) external view returns (uint256);

    /**
     * @dev Permissioned function to set a sender's BPT allowance for a given spender.
     */
    function approve(
        address poolToken,
        address sender,
        address spender,
        uint256 amount
    ) external returns (bool);

    /*******************/
    /*  ERC721 tokens  */
    /*******************/

    /**
     * @dev Returns an account's balance of a Balancer ERC721 token.
     */
    function balanceOfERC721(address token, address owner) external view returns (uint256);

    /**
     * @dev Returns an owner of a Balancer ERC721 token.
     */
    function ownerOfERC721(address token, uint256 tokenId) external view returns (address);

    /**
     * @dev See {IERC721-getApproved}.
     */
    function getApprovedERC721(address token, uint256 tokenId) external view returns (address);

    /**
     * @dev See {IERC721-isApprovedForAll}.
     */
    function isApprovedForAllERC721(
        address token,
        address owner,
        address operator
    ) external view returns (bool);

    /**
     * @dev Can be called only by registered ERC721 pool. See {IERC721-approve}.
     */
    function approveERC721(
        address sender,
        address to,
        uint256 tokenId
    ) external;

    /**
     * @dev Can be called only by registered ERC721 pool. See {IERC721-setApprovalForAll}.
     */
    function setApprovalForAllERC721(
        address sender,
        address operator,
        bool approved
    ) external;

    /**
     * @dev Can be called only by registered ERC721 pool. See {IERC721-transferFrom}.
     */
    function transferFromERC721(
        address sender,
        address from,
        address to,
        uint256 tokenId
    ) external;

    /**
     * @dev Can be called only by registered ERC721 pool. See {IERC721-safeTransferFrom}.
     */
    function safeTransferFromERC721(
        address sender,
        address from,
        address to,
        uint256 tokenId
    ) external;

    /**
     * @dev Can be called only by registered ERC721 pool. See {IERC721-safeTransferFrom}.
     */
    function safeTransferFromERC721(
        address sender,
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) external;
}
