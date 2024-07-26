// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { IVault } from "./IVault.sol";
import { IHooks } from "./IHooks.sol";
import { IProtocolFeeController } from "./IProtocolFeeController.sol";
import "./VaultTypes.sol";

/// @notice Extension of the Vault contract (via the Proxy pattern), intended for less common operations.
interface IVaultExtension {
    /*******************************************************************************
                              Constants and immutables
    *******************************************************************************/

    /// @notice Returns the main Vault address.
    function vault() external view returns (IVault);

    /// @notice Returns the Vault Admin contract address.
    function getVaultAdmin() external view returns (address);

    /*******************************************************************************
                              Transient Accounting
    *******************************************************************************/

    /// @notice Returns True if the Vault is unlocked, false otherwise.
    function isUnlocked() external view returns (bool);

    /**
     *  @notice Returns the count of non-zero deltas.
     *  @return The current value of _nonzeroDeltaCount
     */
    function getNonzeroDeltaCount() external view returns (uint256);

    /**
     * @notice Retrieves the token delta for a specific token.
     * @dev This function allows reading the value from the `_tokenDeltas` mapping.
     * @param token The token for which the delta is being fetched
     * @return The delta of the specified token
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
     * @param swapFeePercentage The initial static swap fee percentage of the pool
     * @param pauseWindowEndTime The timestamp after which it is no longer possible to pause the pool
     * @param protocolFeeExempt If true, the pool's initial aggregate fees will be set to 0
     * @param roleAccounts Addresses the Vault will allow to change certain pool settings
     * @param poolHooksContract Contract that implements the hooks for the pool
     * @param liquidityManagement Liquidity management flags with implemented methods
     */
    function registerPool(
        address pool,
        TokenConfig[] memory tokenConfig,
        uint256 swapFeePercentage,
        uint32 pauseWindowEndTime,
        bool protocolFeeExempt,
        PoolRoleAccounts calldata roleAccounts,
        address poolHooksContract,
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
     * @notice Gets pool token rates.
     * @dev This function performs external calls if tokens are yield-bearing. All returned arrays are in token
     * registration order.
     *
     * @param pool Address of the pool
     * @return decimalScalingFactors Conversion factor used to adjust for token decimals for uniform precision in
     * calculations. FP(1) for 18-decimal tokens
     * @return tokenRates 18-decimal FP values for rate tokens (e.g., yield-bearing), or FP(1) for standard tokens
     */
    function getPoolTokenRates(
        address pool
    ) external view returns (uint256[] memory decimalScalingFactors, uint256[] memory tokenRates);

    /// @notice Returns pool data for a given pool.
    function getPoolData(address pool) external view returns (PoolData memory);

    /**
     * @notice Gets the raw data for a pool: tokens, raw balances, scaling factors.
     * @param pool Address of the pool
     * @return tokens The pool tokens, sorted in registration order
     * @return tokenInfo Token info structs (type, rate provider, yield flag), sorted in pool registration order
     * @return balancesRaw Current native decimal balances of the pool tokens, sorted in pool registration order
     * @return lastBalancesLiveScaled18 Last saved live balances, sorted in token registration order
     */
    function getPoolTokenInfo(
        address pool
    )
        external
        view
        returns (
            IERC20[] memory tokens,
            TokenInfo[] memory tokenInfo,
            uint256[] memory balancesRaw,
            uint256[] memory lastBalancesLiveScaled18
        );

    /**
     * @notice Gets current live balances of a given pool (fixed-point, 18 decimals), corresponding to its tokens in
     * registration order.
     *
     * @param pool Address of the pool
     * @return balancesLiveScaled18 Token balances after paying yield fees, applying decimal scaling and rates
     */
    function getCurrentLiveBalances(address pool) external view returns (uint256[] memory balancesLiveScaled18);

    /**
     * @notice Gets the configuration parameters of a pool.
     * @param pool Address of the pool
     * @return Pool configuration
     */
    function getPoolConfig(address pool) external view returns (PoolConfig memory);

    /**
     * @notice Gets the hooks configuration parameters of a pool.
     * @param pool Address of the pool
     * @return Hooks configuration
     */
    function getHooksConfig(address pool) external view returns (HooksConfig memory);

    /**
     * @notice The current rate of a pool token (BPT) = invariant / totalSupply.
     * @param pool Address of the pool
     * @return rate BPT rate
     */
    function getBptRate(address pool) external view returns (uint256 rate);

    /*******************************************************************************
                                 Balancer Pool Tokens
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
    function getPoolPausedState(address pool) external view returns (bool, uint32, uint32, address);

    /*******************************************************************************
                                          Fees
    *******************************************************************************/

    /**
     * @notice Returns the accumulated swap fees (including aggregate fees) in `token` collected by the pool.
     * @param pool The address of the pool for which aggregate fees have been collected
     * @param token The address of the token in which fees have been accumulated
     * @return The total amount of fees accumulated in the specified token
     */
    function getAggregateSwapFeeAmount(address pool, IERC20 token) external view returns (uint256);

    /**
     * @notice Returns the accumulated yield fees (including aggregate fees) in `token` collected by the pool.
     * @param pool The address of the pool for which aggregate fees have been collected
     * @param token The address of the token in which fees have been accumulated
     * @return The total amount of fees accumulated in the specified token
     */
    function getAggregateYieldFeeAmount(address pool, IERC20 token) external view returns (uint256);

    /**
     * @notice Fetches the static swap fee percentage for a given pool.
     * @param pool The address of the pool whose static swap fee percentage is being queried
     * @return The current static swap fee percentage for the specified pool
     */
    function getStaticSwapFeePercentage(address pool) external view returns (uint256);

    /**
     * @notice Fetches the role accounts for a given pool (pause manager, swap manager, pool creator)
     * @param pool The address of the pool whose roles are being queried
     * @return roleAccounts A struct containing the role accounts for the pool (or 0 if unassigned)
     */
    function getPoolRoleAccounts(address pool) external view returns (PoolRoleAccounts memory);

    /**
     * @notice Query the current dynamic swap fee percentage of a pool, given a set of swap parameters.
     * @param pool The pool
     * @param swapParams The swap parameters used to compute the fee
     * @return success True if the pool has a dynamic swap fee and it can be successfully computed
     * @return dynamicSwapFeePercentage The dynamic swap fee percentage
     */
    function computeDynamicSwapFeePercentage(
        address pool,
        PoolSwapParams memory swapParams
    ) external view returns (bool, uint256);

    /**
     * @notice Returns the Protocol Fee Controller address.
     * @return Address of the ProtocolFeeController
     */
    function getProtocolFeeController() external view returns (IProtocolFeeController);

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
     * This call always reverts, returning the result in the revert reason.
     *
     * @param data Contains function signature and args to be passed to the msg.sender
     */
    function quoteAndRevert(bytes calldata data) external payable;

    /**
     * @notice Checks if the queries enabled on the Vault.
     * @return If true, then queries are disabled
     */
    function isQueryDisabled() external view returns (bool);
}
