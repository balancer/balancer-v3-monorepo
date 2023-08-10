// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { Asset } from "../solidity-utils/misc/Asset.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Interface for the Vault
interface IVault {
    /*******************************************************************************
                                    Pool Registration
    *******************************************************************************/

    /**
     * @notice Registers a new pool
     * @param factory                        Factory address to register pool
     * @param tokens                         Tokens involved in the pool
     */
    function registerPool(address factory, IERC20[] memory tokens) external;

    /**
     * @notice Checks if a pool is registered
     * @param pool                           Address of the pool to check
     * @return                               True if the pool is registered, false otherwise
     */
    function isRegisteredPool(address pool) external view returns (bool);

    /**
     * @notice Gets tokens and their balances of a pool
     * @param pool                           Address of the pool
     * @return tokens                        List of tokens in the pool
     * @return balances                      Corresponding balances of the tokens
     */
    function getPoolTokens(address pool) external view returns (IERC20[] memory tokens, uint256[] memory balances);

    /*******************************************************************************
                                 ERC20 Balancer Pool Tokens 
    *******************************************************************************/

    /**
     * @notice Gets total supply of a given ERC20 token
     * @param token                          Token's address
     * @return                               Total supply of the token
     */
    function totalSupplyOfERC20(address token) external view returns (uint256);

    /**
     * @notice Gets balance of an account for a given ERC20 token
     * @param token                          Token's address
     * @param account                        Account's address
     * @return                               Balance of the account for the token
     */
    function balanceOfERC20(address token, address account) external view returns (uint256);

    /**
     * @notice Transfers ERC20 token from owner to a recipient
     * @param owner                          Owner's address
     * @param to                             Recipient's address
     * @param amount                         Amount of tokens to transfer
     * @return                               True if successful, false otherwise
     */
    function transferERC20(address owner, address to, uint256 amount) external returns (bool);

    /**
     * @notice Transfers from a sender to a recipient using an allowance
     * @param spender                        Address allowed to perform the transfer
     * @param from                           Sender's address
     * @param to                             Recipient's address
     * @param amount                         Amount of tokens to transfer
     * @return                               True if successful, false otherwise
     */
    function transferFromERC20(address spender, address from, address to, uint256 amount) external returns (bool);

    /**
     * @notice Gets allowance of a spender for a given ERC20 token and owner
     * @param token                          Token's address
     * @param owner                          Owner's address
     * @param spender                        Spender's address
     * @return                               Amount of tokens the spender is allowed to spend
     */
    function allowanceOfERC20(address token, address owner, address spender) external view returns (uint256);

    /**
     * @notice Approves a spender to spend tokens on behalf of sender
     * @param sender                         Owner's address
     * @param spender                        Spender's address
     * @param amount                         Amount of tokens to approve
     * @return                               True if successful, false otherwise
     */
    function approveERC20(address sender, address spender, uint256 amount) external returns (bool);

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
    function getNonzeroDeltaCount() external view returns (uint256) ;

    /**
     * @notice Retrieves the token delta for a specific user and token.
     * @dev This function allows reading the value from the `_tokenDeltas` mapping.
     * @param user The address of the user for whom the delta is being fetched.
     * @param token The token for which the delta is being fetched.
     * @return The delta of the specified token for the specified user.
     */
    function getTokenDelta(address user, IERC20 token) external view returns (int256) ;

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
     * @param userData                       Additional user data
     * @return amountsIn                     Actual amounts of input assets
     * @return bptAmountOut                  Output pool token amount
     */
    function addLiquidity(
        address pool,
        IERC20[] memory assets,
        uint256[] memory maxAmountsIn,
        uint256 minBptAmountOut,
        bytes memory userData
    ) external returns (uint256[] memory amountsIn, uint256 bptAmountOut);

    /**
     * @notice Removes liquidity from a pool
     * @param pool                           Address of the pool
     * @param assets                         Assets involved in the liquidity removal
     * @param minAmountsOut                  Minimum amounts of output assets
     * @param bptAmountIn                    Input pool token amount
     * @param userData                       Additional user data
     * @return amountsOut                    Actual amounts of output assets
     */
    function removeLiquidity(
        address pool,
        IERC20[] memory assets,
        uint256[] memory minAmountsOut,
        uint256 bptAmountIn,
        bytes memory userData
    ) external returns (uint256[] memory amountsOut);

    event PoolBalanceChanged(address indexed pool, address indexed liquidityProvider, IERC20[] tokens, int256[] deltas);
}
