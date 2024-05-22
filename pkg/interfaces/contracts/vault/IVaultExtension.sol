// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "./IVault.sol";
import { IBasePool } from "./IBasePool.sol";
import "./VaultTypes.sol";

interface IVaultExtension {
    /*******************************************************************************
                              Constants and immutables
    *******************************************************************************/

    /// @dev Returns the main Vault address.
    function vault() external view returns (IVault);

    /*******************************************************************************
                              Transient Accounting
    *******************************************************************************/

    /**
     * @notice Returns True if the Vault is unlocked, false otherwise.
     */
    function isUnlocked() external view returns (bool);

    /**
     *  @notice Returns the count of non-zero deltas.
     *  @return The current value of _nonzeroDeltaCount
     */
    function getNonzeroDeltaCount() external view returns (uint256);

    /**
     * @notice Retrieves the token delta for a specific user and token.
     * @dev This function allows reading the value from the `_tokenDeltas` mapping.
     * @param token The token for which the delta is being fetched
     * @return The delta of the specified token for the specified user
     */
    function getTokenDelta(IERC20 token) external view returns (int256);

    /**
     * @notice Retrieves the reserve (i.e., total Vault balance) of a given token.
     * @param token The token for which to retrieve the reserve
     * @return The amount of reserves for the given token
     */
    function getReservesOf(IERC20 token) external view returns (uint256);

    /*******************************************************************************
                                    Pool Registration
    *******************************************************************************/

    /**
     * @notice Registers a pool, associating it with its factory and the tokens it manages.
     * @dev A pool can opt-out of pausing by providing a zero value for the pause window, or allow pausing indefinitely
     * by providing a large value. (Pool pause windows are not limited by the Vault maximums.) The vault defines an
     * additional buffer period during which a paused pool will stay paused. After the buffer period passes, a paused
     * pool will automatically unpause.
     *
     * A pool can opt out of Balancer governance pausing by providing a custom `pauseManager`. This might be a
     * multi-sig contract or an arbitrary smart contract with its own access controls, that forwards calls to
     * the Vault.
     *
     * If the zero address is provided for the `pauseManager`, permissions for pausing the pool will default to the
     * authorizer.
     *
     * @param pool The address of the pool being registered
     * @param tokenConfig An array of descriptors for the tokens the pool will manage
     * @param swapFeePercentage Initial value of the swap fee
     * @param pauseWindowEndTime The timestamp after which it is no longer possible to pause the pool
     * @param roleAccounts Addresses the Vault will allow to change certain pool settings
     * @param poolHooksFlags Flags indicating which hooks the pool supports
     * @param liquidityManagement Liquidity management flags with implemented methods
     */
    function registerPool(
        address pool,
        TokenConfig[] memory tokenConfig,
        uint256 swapFeePercentage,
        uint256 pauseWindowEndTime,
        PoolRoleAccounts calldata roleAccounts,
        PoolHooksFlags calldata poolHooksFlags,
        LiquidityManagement calldata liquidityManagement
    ) external;

    /**
     * @notice Checks whether a pool is registered.
     * @param pool Address of the pool to check
     * @return True if the pool is registered, false otherwise
     */
    function isPoolRegistered(address pool) external view returns (bool);

    /**
     * @notice Initializes a registered pool by adding liquidity; mints BPT tokens for the first time in exchange.
     * @param pool Address of the pool to initialize
     * @param to Address that will receive the output BPT
     * @param tokens Tokens used to seed the pool (must match the registered tokens)
     * @param exactAmountsIn Exact amounts of input tokens
     * @param minBptAmountOut Minimum amount of output pool tokens
     * @param userData Additional (optional) data required for adding initial liquidity
     * @return bptAmountOut Output pool token amount
     */
    function initialize(
        address pool,
        address to,
        IERC20[] memory tokens,
        uint256[] memory exactAmountsIn,
        uint256 minBptAmountOut,
        bytes memory userData
    ) external returns (uint256 bptAmountOut);

    /*******************************************************************************
                                    Pool Information
    *******************************************************************************/

    /**
     * @notice Checks whether a pool is initialized.
     * @dev An initialized pool can be considered registered as well.
     * @param pool Address of the pool to check
     * @return True if the pool is initialized, false otherwise
     */
    function isPoolInitialized(address pool) external view returns (bool);

    /**
     * @notice Gets the tokens registered to a pool.
     * @param pool Address of the pool
     * @return tokens List of tokens in the pool
     */
    function getPoolTokens(address pool) external view returns (IERC20[] memory);

    /**
     * @notice Gets the raw data for a pool: tokens, raw balances, scaling factors.
     * @return tokenConfig Pool's token configuration
     * @return balancesRaw Corresponding raw balances of the tokens
     * @return scalingFactors Corresponding scalingFactors of the tokens
     */
    function getPoolTokenInfo(
        address pool
    )
        external
        view
        returns (TokenConfig[] memory tokenConfig, uint256[] memory balancesRaw, uint256[] memory scalingFactors);

    /**
     * @notice Gets the configuration parameters of a pool.
     * @param pool Address of the pool
     * @return Pool configuration
     */
    function getPoolConfig(address pool) external view returns (PoolConfig memory);

    /*******************************************************************************
                                    Pool Tokens
    *******************************************************************************/

    /**
     * @notice Gets total supply of a given ERC20 token.
     * @param token Token's address
     * @return Total supply of the token
     */
    function totalSupply(address token) external view returns (uint256);

    /**
     * @notice Gets balance of an account for a given ERC20 token.
     * @param token Token's address
     * @param account Account's address
     * @return Balance of the account for the token
     */
    function balanceOf(address token, address account) external view returns (uint256);

    /**
     * @notice Gets allowance of a spender for a given ERC20 token and owner.
     * @param token Token's address
     * @param owner Owner's address
     * @param spender Spender's address
     * @return Amount of tokens the spender is allowed to spend
     */
    function allowance(address token, address owner, address spender) external view returns (uint256);

    /**
     * @notice Transfers pool token from owner to a recipient.
     * @dev Notice that the pool token address is not included in the params. This function is exclusively called by
     * the pool contract, so msg.sender is used as the token address.
     *
     * @param owner Owner's address
     * @param to Recipient's address
     * @param amount Amount of tokens to transfer
     * @return True if successful, false otherwise
     */
    function transfer(address owner, address to, uint256 amount) external returns (bool);

    /**
     * @notice Transfers pool token from a sender to a recipient using an allowance.
     * @dev Notice that the pool token address is not included in the params. This function is exclusively called by
     * the pool contract, so msg.sender is used as the token address.
     *
     * @param spender Address allowed to perform the transfer
     * @param from Sender's address
     * @param to Recipient's address
     * @param amount Amount of tokens to transfer
     * @return True if successful, false otherwise
     */
    function transferFrom(address spender, address from, address to, uint256 amount) external returns (bool);

    /**
     * @notice Approves a spender to spend pool tokens on behalf of sender.
     * @dev Notice that the pool token address is not included in the params. This function is exclusively called by
     * the pool contract, so msg.sender is used as the token address.
     *
     * @param owner Owner's address
     * @param spender Spender's address
     * @param amount Amount of tokens to approve
     * @return True if successful, false otherwise
     */
    function approve(address owner, address spender, uint256 amount) external returns (bool);

    /*******************************************************************************
                                    Pool Pausing
    *******************************************************************************/

    /**
     * @notice Indicates whether a pool is paused.
     * @param pool The pool to be checked
     * @return True if the pool is paused
     */
    function isPoolPaused(address pool) external view returns (bool);

    /**
     * @notice Returns the paused status, and end times of the Pool's pause window and buffer period.
     * @dev Note that even when set to a paused state, the pool will automatically unpause at the end of
     * the buffer period.
     *
     * @param pool The pool whose data is requested
     * @return paused True if the Pool is paused
     * @return poolPauseWindowEndTime The timestamp of the end of the Pool's pause window
     * @return poolBufferPeriodEndTime The timestamp after which the Pool unpauses itself (if paused)
     * @return pauseManager The pause manager, or the zero address
     */
    function getPoolPausedState(address pool) external view returns (bool, uint256, uint256, address);

    /*******************************************************************************
                                   Fees
    *******************************************************************************/

    /**
     * @notice Retrieves the current protocol swap fee percentage.
     * @return The current protocol swap fee percentage
     */
    function getProtocolSwapFeePercentage() external view returns (uint256);

    /**
     * @notice Retrieves the current protocol yield fee percentage.
     * @return The current protocol yield fee percentage
     */
    function getProtocolYieldFeePercentage() external view returns (uint256);

    /**
     * @notice Returns the accumulated swap and yield fee in `token` collected by the protocol for a given pool.
     * @param pool The address of the pool for which protocol fees have been collected
     * @param token The address of the token in which fees have been accumulated
     * @return The total amount of fees accumulated in the specified token
     */
    function getProtocolFees(address pool, IERC20 token) external view returns (uint256);

    /**
     * @notice Fetches the static swap fee percentage for a given pool.
     * @param pool The address of the pool whose static swap fee percentage is being queried
     * @return The current static swap fee percentage for the specified pool
     */
    function getStaticSwapFeePercentage(address pool) external view returns (uint256);

    /**
     * @notice Fetches the static swap fee manager for a given pool (or zero).
     * @param pool The address of the pool whose static swap fee manager is being queried
     * @return The current static swap fee manager for the specified pool
     */
    function getStaticSwapFeeManager(address pool) external view returns (address);

    /**
     * @notice Returns the accumulated swap and yield fee in `token` for the given pool, collected for the creator.
     * @param pool The address of the pool whose creator fee is being queried
     * @param token The token in which the creator fee was charged
     * @return poolCreatorFee The creator fee of the pool and token
     */
    function getPoolCreatorFees(address pool, IERC20 token) external returns (uint256 poolCreatorFee);

    /**
     * @notice Fetches the address of the creator of a pool, who can collect creator fees.
     * @param pool The address of the pool whose creator is being queried
     * @return poolCreator The address of the creator
     */
    function getPoolCreator(address pool) external returns (address poolCreator);

    /**
     * @notice Query the current dynamic swap fee of a pool, given a set of swap parameters.
     * @param pool The pool
     * @param swapParams The swap parameters used to compute the fee
     * @return success True if the pool has a dynamic swap fee and it can be successfully computed
     * @return dynamicSwapFee The dynamic swap fee percentage
     */
    function computeDynamicSwapFee(
        address pool,
        IBasePool.PoolSwapParams memory swapParams
    ) external view returns (bool, uint256);

    /*******************************************************************************
                                    Recovery Mode
    *******************************************************************************/

    /**
     * @notice Checks whether a pool is in recovery mode.
     * @param pool Address of the pool to check
     * @return True if the pool is initialized, false otherwise
     */
    function isPoolInRecoveryMode(address pool) external view returns (bool);

    /**
     * @notice Remove liquidity from a pool specifying exact pool tokens in, with proportional token amounts out.
     * The request is implemented by the Vault without any interaction with the pool, ensuring that
     * it works the same for all pools, and cannot be disabled by a new pool type.
     *
     * @param pool Address of the pool
     * @param from Address of user to burn pool tokens from
     * @param exactBptAmountIn Input pool token amount
     * @return amountsOut Actual calculated amounts of output tokens, sorted in token registration order
     */
    function removeLiquidityRecovery(
        address pool,
        address from,
        uint256 exactBptAmountIn
    ) external returns (uint256[] memory amountsOut);

    /*******************************************************************************
                                    Queries
    *******************************************************************************/

    /**
     * @notice Performs a callback on msg.sender with arguments provided in `data`.
     * @dev Used to query a set of operations on the Vault. Only off-chain eth_call are allowed,
     * anything else will revert.
     *
     * Allows querying any operation on the Vault that has the `onlyWhenUnlocked` modifier.
     *
     * Allows the external calling of a function via the Vault contract to
     * access Vault's functions guarded by `onlyWhenUnlocked`.
     * `transient` modifier ensuring balances changes within the Vault are settled.
     *
     * @param data Contains function signature and args to be passed to the msg.sender
     * @return result Resulting data from the call
     */
    function quote(bytes calldata data) external payable returns (bytes memory result);

    /**
     * @notice Checks if the queries enabled on the Vault.
     * @return If true, then queries are disabled
     */
    function isQueryDisabled() external view returns (bool);

    /*******************************************************************************
                                     Miscellaneous
    *******************************************************************************/

    /**
     * @notice Returns the Vault Admin contract address.
     */
    function getVaultAdmin() external view returns (address);
}
