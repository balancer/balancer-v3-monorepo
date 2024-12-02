// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IProtocolFeeController } from "./IProtocolFeeController.sol";
import { IVault } from "./IVault.sol";
import { IHooks } from "./IHooks.sol";
import "./VaultTypes.sol";

/**
 * @notice Interface for functions defined on the `VaultExtension` contract.
 * @dev `VaultExtension` handles less critical or frequently used functions, since delegate calls through
 * the Vault are more expensive than direct calls. The main Vault contains the core code for swaps and
 * liquidity operations.
 */
interface IVaultExtension {
    /*******************************************************************************
                              Constants and immutables
    *******************************************************************************/

    /**
     * @notice Returns the main Vault address.
     * @dev The main Vault contains the entrypoint and main liquidity operation implementations.
     * @return vault The address of the main Vault
     */
    function vault() external view returns (IVault);

    /**
     * @notice Returns the VaultAdmin contract address.
     * @dev The VaultAdmin contract mostly implements permissioned functions.
     * @return vaultAdmin The address of the Vault admin
     */
    function getVaultAdmin() external view returns (address vaultAdmin);

    /*******************************************************************************
                              Transient Accounting
    *******************************************************************************/

    /**
     * @notice Returns whether the Vault is unlocked (i.e., executing an operation).
     * @dev The Vault must be unlocked to perform state-changing liquidity operations.
     * @return unlocked True if the Vault is unlocked, false otherwise
     */
    function isUnlocked() external view returns (bool unlocked);

    /**
     *  @notice Returns the count of non-zero deltas.
     *  @return nonzeroDeltaCount The current value of `_nonzeroDeltaCount`
     */
    function getNonzeroDeltaCount() external view returns (uint256 nonzeroDeltaCount);

    /**
     * @notice Retrieves the token delta for a specific token.
     * @dev This function allows reading the value from the `_tokenDeltas` mapping.
     * @param token The token for which the delta is being fetched
     * @return tokenDelta The delta of the specified token
     */
    function getTokenDelta(IERC20 token) external view returns (int256 tokenDelta);

    /**
     * @notice Retrieves the reserve (i.e., total Vault balance) of a given token.
     * @param token The token for which to retrieve the reserve
     * @return reserveAmount The amount of reserves for the given token
     */
    function getReservesOf(IERC20 token) external view returns (uint256 reserveAmount);

    /**
     * @notice This flag is used to detect and tax "round trip" transactions (adding and removing liquidity in the
     * same pool).
     * @dev Taxing remove liquidity proportional whenever liquidity was added in the same transaction adds an extra
     * layer of security, discouraging operations that try to undo others for profit. Remove liquidity proportional
     * is the only standard way to exit a position without fees, and this flag is used to enable fees in that case.
     * It also discourages indirect swaps via unbalanced add and remove proportional, as they are expected to be worse
     * than a simple swap for every pool type.
     *
     * @param pool Address of the pool to check
     * @return liquidityAdded True if liquidity has been added to this pool in the current transaction
     */
    function getAddLiquidityCalledFlag(address pool) external view returns (bool liquidityAdded);

    /*******************************************************************************
                                    Pool Registration
    *******************************************************************************/

    /**
     * @notice Registers a pool, associating it with its factory and the tokens it manages.
     * @dev A pool can opt-out of pausing by providing a zero value for the pause window, or allow pausing indefinitely
     * by providing a large value. (Pool pause windows are not limited by the Vault maximums.) The vault defines an
     * additional buffer period during which a paused pool will stay paused. After the buffer period passes, a paused
     * pool will automatically unpause. Balancer timestamps are 32 bits.
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
     * @return registered True if the pool is registered, false otherwise
     */
    function isPoolRegistered(address pool) external view returns (bool registered);

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
     * @return initialized True if the pool is initialized, false otherwise
     */
    function isPoolInitialized(address pool) external view returns (bool initialized);

    /**
     * @notice Gets the tokens registered to a pool.
     * @param pool Address of the pool
     * @return tokens List of tokens in the pool
     */
    function getPoolTokens(address pool) external view returns (IERC20[] memory tokens);

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

    /**
     * @notice Returns comprehensive pool data for the given pool.
     * @dev This contains the pool configuration (flags), tokens and token types, rates, scaling factors, and balances.
     * @param pool The address of the pool
     * @return poolData The `PoolData` result
     */
    function getPoolData(address pool) external view returns (PoolData memory poolData);

    /**
     * @notice Gets the raw data for a pool: tokens, raw balances, scaling factors.
     * @param pool Address of the pool
     * @return tokens The pool tokens, sorted in registration order
     * @return tokenInfo Token info structs (type, rate provider, yield flag), sorted in token registration order
     * @return balancesRaw Current native decimal balances of the pool tokens, sorted in token registration order
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
     * @dev The `PoolConfig` contains liquidity management and other state flags, fee percentages, the pause window.
     * @param pool Address of the pool
     * @return poolConfig The pool configuration as a `PoolConfig` struct
     */
    function getPoolConfig(address pool) external view returns (PoolConfig memory poolConfig);

    /**
     * @notice Gets the hooks configuration parameters of a pool.
     * @dev The `HooksConfig` contains flags indicating which pool hooks are implemented.
     * @param pool Address of the pool
     * @return hooksConfig The hooks configuration as a `HooksConfig` struct
     */
    function getHooksConfig(address pool) external view returns (HooksConfig memory hooksConfig);

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
     * @notice Gets the total supply of a given ERC20 token.
     * @param token The token address
     * @return totalSupply Total supply of the token
     */
    function totalSupply(address token) external view returns (uint256);

    /**
     * @notice Gets the balance of an account for a given ERC20 token.
     * @param token Address of the token
     * @param account Address of the account
     * @return balance Balance of the account for the token
     */
    function balanceOf(address token, address account) external view returns (uint256 balance);

    /**
     * @notice Gets the allowance of a spender for a given ERC20 token and owner.
     * @param token Address of the token
     * @param owner Address of the owner
     * @param spender Address of the spender
     * @return allowance Amount of tokens the spender is allowed to spend
     */
    function allowance(address token, address owner, address spender) external view returns (uint256);

    /**
     * @notice Approves a spender to spend pool tokens on behalf of sender.
     * @dev Notice that the pool token address is not included in the params. This function is exclusively called by
     * the pool contract, so msg.sender is used as the token address.
     *
     * @param owner Address of the owner
     * @param spender Address of the spender
     * @param amount Amount of tokens to approve
     * @return success True if successful, false otherwise
     */
    function approve(address owner, address spender, uint256 amount) external returns (bool success);

    /*******************************************************************************
                                     Pool Pausing
    *******************************************************************************/

    /**
     * @notice Indicates whether a pool is paused.
     * @dev If a pool is paused, all non-Recovery Mode state-changing operations will revert.
     * @param pool The pool to be checked
     * @return poolPaused True if the pool is paused
     */
    function isPoolPaused(address pool) external view returns (bool poolPaused);

    /**
     * @notice Returns the paused status, and end times of the Pool's pause window and buffer period.
     * @dev Note that even when set to a paused state, the pool will automatically unpause at the end of
     * the buffer period. Balancer timestamps are 32 bits.
     *
     * @param pool The pool whose data is requested
     * @return poolPaused True if the Pool is paused
     * @return poolPauseWindowEndTime The timestamp of the end of the Pool's pause window
     * @return poolBufferPeriodEndTime The timestamp after which the Pool unpauses itself (if paused)
     * @return pauseManager The pause manager, or the zero address
     */
    function getPoolPausedState(
        address pool
    )
        external
        view
        returns (bool poolPaused, uint32 poolPauseWindowEndTime, uint32 poolBufferPeriodEndTime, address pauseManager);

    /*******************************************************************************
                                   ERC4626 Buffers
    *******************************************************************************/

    /**
     * @notice Checks if the wrapped token has an initialized buffer in the Vault.
     * @dev An initialized buffer should have an asset registered in the Vault.
     * @param wrappedToken Address of the wrapped token that implements IERC4626
     * @return isBufferInitialized True if the ERC4626 buffer is initialized
     */
    function isERC4626BufferInitialized(IERC4626 wrappedToken) external view returns (bool isBufferInitialized);

    /**
     * @notice Gets the registered asset for a given buffer.
     * @dev To avoid malicious wrappers (e.g., that might potentially change their asset after deployment), routers
     * should never call `wrapper.asset()` directly, at least without checking it against the asset registered with
     * the Vault on initialization.
     *
     * @param wrappedToken The wrapped token specifying the buffer
     * @return asset The underlying asset of the wrapped token
     */
    function getERC4626BufferAsset(IERC4626 wrappedToken) external view returns (address asset);

    /*******************************************************************************
                                          Fees
    *******************************************************************************/

    /**
     * @notice Returns the accumulated swap fees (including aggregate fees) in `token` collected by the pool.
     * @param pool The address of the pool for which aggregate fees have been collected
     * @param token The address of the token in which fees have been accumulated
     * @return swapFeeAmount The total amount of fees accumulated in the specified token
     */
    function getAggregateSwapFeeAmount(address pool, IERC20 token) external view returns (uint256 swapFeeAmount);

    /**
     * @notice Returns the accumulated yield fees (including aggregate fees) in `token` collected by the pool.
     * @param pool The address of the pool for which aggregate fees have been collected
     * @param token The address of the token in which fees have been accumulated
     * @return yieldFeeAmount The total amount of fees accumulated in the specified token
     */
    function getAggregateYieldFeeAmount(address pool, IERC20 token) external view returns (uint256 yieldFeeAmount);

    /**
     * @notice Fetches the static swap fee percentage for a given pool.
     * @param pool The address of the pool whose static swap fee percentage is being queried
     * @return swapFeePercentage The current static swap fee percentage for the specified pool
     */
    function getStaticSwapFeePercentage(address pool) external view returns (uint256 swapFeePercentage);

    /**
     * @notice Fetches the role accounts for a given pool (pause manager, swap manager, pool creator)
     * @param pool The address of the pool whose roles are being queried
     * @return roleAccounts A struct containing the role accounts for the pool (or 0 if unassigned)
     */
    function getPoolRoleAccounts(address pool) external view returns (PoolRoleAccounts memory roleAccounts);

    /**
     * @notice Query the current dynamic swap fee percentage of a pool, given a set of swap parameters.
     * @dev Reverts if the hook doesn't return the success flag set to `true`.
     * @param pool The pool
     * @param swapParams The swap parameters used to compute the fee
     * @return dynamicSwapFeePercentage The dynamic swap fee percentage
     */
    function computeDynamicSwapFeePercentage(
        address pool,
        PoolSwapParams memory swapParams
    ) external view returns (uint256 dynamicSwapFeePercentage);

    /**
     * @notice Returns the Protocol Fee Controller address.
     * @return protocolFeeController Address of the ProtocolFeeController
     */
    function getProtocolFeeController() external view returns (IProtocolFeeController protocolFeeController);

    /*******************************************************************************
                                     Recovery Mode
    *******************************************************************************/

    /**
     * @notice Checks whether a pool is in Recovery Mode.
     * @dev Recovery Mode enables a safe proportional withdrawal path, with no external calls.
     * @param pool Address of the pool to check
     * @return inRecoveryMode True if the pool is in Recovery Mode, false otherwise
     */
    function isPoolInRecoveryMode(address pool) external view returns (bool inRecoveryMode);

    /**
     * @notice Remove liquidity from a pool specifying exact pool tokens in, with proportional token amounts out.
     * The request is implemented by the Vault without any interaction with the pool, ensuring that
     * it works the same for all pools, and cannot be disabled by a new pool type.
     *
     * @param pool Address of the pool
     * @param from Address of user to burn pool tokens from
     * @param exactBptAmountIn Input pool token amount
     * @param minAmountsOut Minimum amounts of tokens to be received, sorted in token registration order
     * @return amountsOut Actual calculated amounts of output tokens, sorted in token registration order
     */
    function removeLiquidityRecovery(
        address pool,
        address from,
        uint256 exactBptAmountIn,
        uint256[] memory minAmountsOut
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
    function quote(bytes calldata data) external returns (bytes memory result);

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
    function quoteAndRevert(bytes calldata data) external;

    /**
     * @notice Returns true if queries are disabled on the Vault.
     * @return queryDisabled True if queries are disabled (either temporarily or permanently)
     */
    function isQueryDisabled() external view returns (bool queryDisabled);

    /**
     * @notice Returns true if queries are disabled permanently; false if they are enabled.
     * @dev This is a one-way switch. Once queries are disabled permanently, they can never be re-enabled.
     * @return queryDisabledPermanently True if queries are permanently disabled
     */
    function isQueryDisabledPermanently() external view returns (bool queryDisabledPermanently);

    /**
     * @notice Pools can use this event to emit event data from the Vault.
     * @param eventKey Event key
     * @param eventData Encoded event data
     */
    function emitAuxiliaryEvent(bytes32 eventKey, bytes calldata eventData) external;
}
