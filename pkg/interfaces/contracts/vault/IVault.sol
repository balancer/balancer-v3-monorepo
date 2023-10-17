// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IBasePool } from "./IBasePool.sol";
import { Asset } from "../solidity-utils/misc/Asset.sol";
import { IAuthorizer } from "./IAuthorizer.sol";

/// @notice Represents a pool's hooks to be called
struct PoolHooks {
    bool shouldCallAfterSwap;
    bool shouldCallAfterAddLiquidity;
    bool shouldCallAfterRemoveLiquidity;
}

/// @notice Represents a pool's configuration
struct PoolConfig {
    bool isRegisteredPool;
    bool isInitializedPool;
    bool hasDynamicSwapFee;
    uint24 staticSwapFee;
    PoolHooks hooks;
}

/// @notice Interface for the Vault
interface IVault {
    /*******************************************************************************
                                    Pool Registration
    *******************************************************************************/

    function initialize(
        address pool,
        IERC20[] memory tokens,
        uint256[] memory maxAmountsIn,
        bytes memory userData
    ) external returns (uint256[] memory, uint256 bptAmountOut);

    /**
     * @notice Registers a pool, associating it with its factory and the tokens it manages.
     * @param factory The factory address associated with the pool being registered.
     * @param tokens An array of token addresses the pool will manage.
     * @param config Config for the pool
     */
    function registerPool(address factory, IERC20[] memory tokens, PoolHooks calldata config) external;

    /**
     * @notice Checks if a pool is registered
     * @param pool                           Address of the pool to check
     * @return                               True if the pool is registered, false otherwise
     */
    function isRegisteredPool(address pool) external view returns (bool);

    /**
     * @notice Checks if a pool is initialized
     * @param pool                           Address of the pool to check
     * @return                               True if the pool is initialized, false otherwise
     */
    function isInitializedPool(address pool) external view returns (bool);

    /**
     * @notice Gets tokens and their balances of a pool
     * @param pool                           Address of the pool
     * @return tokens                        List of tokens in the pool
     * @return balances                      Corresponding balances of the tokens
     */
    function getPoolTokens(address pool) external view returns (IERC20[] memory tokens, uint256[] memory balances);

    /**
     * @notice Gets config of a pool
     * @param pool                           Address of the pool
     * @return                               Config for the pool
     */
    function getPoolConfig(address pool) external view returns (PoolConfig memory);

    /// @notice Emitted when a Pool is registered by calling `registerPool`.
    event PoolRegistered(address indexed pool, address indexed factory, IERC20[] tokens);

    /// @notice Emitted when a Pool is initialized by calling `initialize`.
    event PoolInitialized(address indexed pool);

    /*******************************************************************************
                                    MultiToken
    *******************************************************************************/

    /**
     * @notice Gets total supply of a given ERC20 token
     * @param token                          Token's address
     * @return                               Total supply of the token
     */
    function totalSupply(address token) external view returns (uint256);

    /**
     * @notice Gets balance of an account for a given ERC20 token
     * @param token                          Token's address
     * @param account                        Account's address
     * @return                               Balance of the account for the token
     */
    function balanceOf(address token, address account) external view returns (uint256);

    /**
     * @notice Transfers pool token from owner to a recipient.
     * @dev Notice that the pool token address is not included in the params. This function is exclusively called by
     * the pool contract, so msg.sender is used as the token address.
     * @param owner                          Owner's address
     * @param to                             Recipient's address
     * @param amount                         Amount of tokens to transfer
     * @return                               True if successful, false otherwise
     */
    function transfer(address owner, address to, uint256 amount) external returns (bool);

    /**
     * @notice Transfers pool token from a sender to a recipient using an allowance
     * @dev Notice that the pool token address is not included in the params. This function is exclusively called by
     * the pool contract, so msg.sender is used as the token address.
     * @param spender                        Address allowed to perform the transfer
     * @param from                           Sender's address
     * @param to                             Recipient's address
     * @param amount                         Amount of tokens to transfer
     * @return                               True if successful, false otherwise
     */
    function transferFrom(address spender, address from, address to, uint256 amount) external returns (bool);

    /**
     * @notice Gets allowance of a spender for a given ERC20 token and owner
     * @param token                          Token's address
     * @param owner                          Owner's address
     * @param spender                        Spender's address
     * @return                               Amount of tokens the spender is allowed to spend
     */
    function allowance(address token, address owner, address spender) external view returns (uint256);

    /**
     * @notice Approves a spender to spend pool tokens on behalf of sender
     * @dev Notice that the pool token address is not included in the params. This function is exclusively called by
     * the pool contract, so msg.sender is used as the token address.
     * @param owner                          Owner's address
     * @param spender                        Spender's address
     * @param amount                         Amount of tokens to approve
     * @return                               True if successful, false otherwise
     */
    function approve(address owner, address spender, uint256 amount) external returns (bool);

    /*******************************************************************************
                              Transient Accounting
    *******************************************************************************/

    /**
     * @notice Invokes a callback on msg.sender with arguments provided in `data`.
     * Callback is `transient`, meaning all balances for the caller have to be settled at the end.
     * @param data                           Contain function signature and args to be passed to the msg.sender
     * @return result                        Resulting data from the call
     */
    function invoke(bytes calldata data) external payable returns (bytes memory result);

    /**
     * @notice Settles deltas for a token
     * @param token                          Token's address
     * @return paid                          Amount paid during settlement
     */
    function settle(IERC20 token) external returns (uint256 paid);

    /**
     * @notice Sends tokens to a recipient
     * @param token                          Token's address
     * @param to                             Recipient's address
     * @param amount                         Amount of tokens to send
     */
    function wire(IERC20 token, address to, uint256 amount) external;

    /**
     * @notice Mints tokens to a recipient
     * @param token                          Token's address
     * @param to                             Recipient's address
     * @param amount                         Amount of tokens to mint
     */
    function mint(IERC20 token, address to, uint256 amount) external;

    /**
     * @notice Retrieves tokens from a sender
     * @param token                          Token's address
     * @param from                           Sender's address
     * @param amount                         Amount of tokens to retrieve
     */
    function retrieve(IERC20 token, address from, uint256 amount) external;

    /**
     * @notice Burns tokens from an owner
     * @param token                          Token's address
     * @param owner                          Owner's address
     * @param amount                         Amount of tokens to burn
     */
    function burn(IERC20 token, address owner, uint256 amount) external;

    /**
     * @dev Returns the address at the specified index of the _handlers array.
     * @param index The index of the handler's address to fetch.
     * @return The address at the given index.
     */
    function getHandler(uint256 index) external view returns (address);

    /**
     * @dev Returns the total number of handlers.
     * @return The number of handlers.
     */
    function getHandlersCount() external view returns (uint256);

    /**
     *  @notice Returns the count of non-zero deltas
     *  @return The current value of _nonzeroDeltaCount
     */
    function getNonzeroDeltaCount() external view returns (uint256);

    /**
     * @notice Retrieves the token delta for a specific user and token.
     * @dev This function allows reading the value from the `_tokenDeltas` mapping.
     * @param user The address of the user for whom the delta is being fetched.
     * @param token The token for which the delta is being fetched.
     * @return The delta of the specified token for the specified user.
     */
    function getTokenDelta(address user, IERC20 token) external view returns (int256);

    /**
     * @notice Retrieves the reserve of a given token.
     * @param token The token for which to retrieve the reserve.
     * @return The amount of reserves for the given token.
     */
    function getTokenReserve(IERC20 token) external view returns (uint256);

    enum SwapKind {
        GIVEN_IN,
        GIVEN_OUT
    }

    /**
     * @notice Swaps tokens based on provided parameters
     * @param params                         Parameters for the swap
     * @return amountCalculated              Calculated swap amount
     * @return amountIn                      Amount of input tokens for the swap
     * @return amountOut                     Amount of output tokens from the swap
     */
    function swap(
        SwapParams memory params
    ) external returns (uint256 amountCalculated, uint256 amountIn, uint256 amountOut);

    struct SwapParams {
        /// @notice Type of the swap.
        SwapKind kind;
        /// @notice Address of the pool.
        address pool;
        /// @notice Token given in the swap.
        IERC20 tokenIn;
        /// @notice Token received from the swap.
        IERC20 tokenOut;
        /// @notice Amount of token given.
        uint256 amountGiven;
        /// @notice Additional data for the swap.
        bytes userData;
    }

    event Swap(
        address indexed pool,
        IERC20 indexed tokenIn,
        IERC20 indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut
    );

    /**
     * @notice Adds liquidity to a pool
     * @param pool                           Address of the pool
     * @param assets                         Assets involved in the liquidity
     * @param maxAmountsIn                   Maximum amounts of input assets
     * @param minBptAmountOut                Minimum output pool token amount
     * @param kind                           Add liquidity kind
     * @param userData                       Additional user data
     * @return amountsIn                     Actual amounts of input assets
     * @return bptAmountOut                  Output pool token amount
     */
    function addLiquidity(
        address pool,
        IERC20[] memory assets,
        uint256[] memory maxAmountsIn,
        uint256 minBptAmountOut,
        IBasePool.AddLiquidityKind kind,
        bytes memory userData
    ) external returns (uint256[] memory amountsIn, uint256 bptAmountOut);

    /**
     * @notice Removes liquidity from a pool
     * @param pool                           Address of the pool
     * @param assets                         Assets involved in the liquidity removal
     * @param minAmountsOut                  Minimum amounts of output assets
     * @param maxBptAmountIn                 Input pool token amount
     * @param kind                           Remove liquidity kind
     * @param userData                       Additional user data
     * @return amountsOut                    Actual amounts of output assets
     * @return bptAmountIn                   Actual amount of BPT burnt
     */
    function removeLiquidity(
        address pool,
        IERC20[] memory assets,
        uint256[] memory minAmountsOut,
        uint256 maxBptAmountIn,
        IBasePool.RemoveLiquidityKind kind,
        bytes memory userData
    ) external returns (uint256[] memory amountsOut, uint256 bptAmountIn);

    event PoolBalanceChanged(address indexed pool, address indexed liquidityProvider, IERC20[] tokens, int256[] deltas);

    /*******************************************************************************
                                   Fees
    *******************************************************************************/

    /**
     * @notice Sets new swap fee percentage for the protocol.
     * @param newSwapFeePercentage  New swap fee percentage
     */
    function setProtocolSwapFeePercentage(uint256 newSwapFeePercentage) external;

    event ProtocolSwapFeePercentageChanged(uint256 swapFeePercentage);

    /**
     * @notice Returns current swap fee percentage for the protocol
     * @return Current swap fee percentage
     */
    function getProtocolSwapFeePercentage() external view returns (uint256);

    /**
     * @notice Sets new swap fee percentage for the pool.
     * @param pool                  Pool address to change swap fee for.
     * @param swapFeePercentage  New swap fee percentage
     */
    function setSwapFeePercentage(address pool, uint24 swapFeePercentage) external;

    event SwapFeePercentageChanged(uint24 swapFeePercentage);

    /*******************************************************************************
                                Authentication
    *******************************************************************************/

    /// @dev Returns the Vault's Authorizer.
    function getAuthorizer() external view returns (IAuthorizer);

    /**
     * @dev Sets a new Authorizer for the Vault. The caller must be allowed by the current Authorizer to do this.
     *
     * Emits an `AuthorizerChanged` event.
     */
    function setAuthorizer(IAuthorizer newAuthorizer) external;

    /// @dev Emitted when a new authorizer is set by `setAuthorizer`.
    event AuthorizerChanged(IAuthorizer indexed newAuthorizer);

    /*******************************************************************************
                                    Queries
    *******************************************************************************/

    /**
     * @notice Invokes a callback on msg.sender with arguments provided in `data`
     * to query a set of operations on the Vault.
     * Only off-chain eth_call are allowed, everything else will revert.
     * @param data                           Contain function signature and args to be passed to the msg.sender
     * @return result                        Resulting data from the call
     */
    function quote(bytes calldata data) external payable returns (bytes memory result);

    /// @notice Disables queries functionality on the Vault. Can be called only by governance.
    function disableQuery() external;

    /**
     * @notice Checks if the queries enabled on the Vault.
     * @return If true, then queries are disabled.
     */
    function isQueryDisabled() external view returns (bool);
}
