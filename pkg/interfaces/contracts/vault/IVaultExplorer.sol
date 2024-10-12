// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { TokenInfo, PoolRoleAccounts, PoolData, PoolConfig, PoolSwapParams, HooksConfig } from "./VaultTypes.sol";

/**
 * @notice Helper contract that exposes the full permissionless Vault interface.
 * @dev Since the Vault is split across three contracts using the Proxy pattern, there is not much on the Vault
 * contract itself that can be called directly, especially since it is designed to primarily use a single entrypoint
 * for liquidity operations, invoked through a Router. This is unhelpful for off-chain processes (e.g., Etherscan).
 * The proxy contracts (`VaultExtension` and `VaultAdmin`) can only be delegate-called through the main Vault, so
 * although the functions are visible off-chain, they cannot be called from Etherscan.
 *
 * The `VaultExplorer` performs the delegate calls, in order to expose the entire Vault interface in a user-friendly
 * manner. It exposes all the "getters," plus permissionless write operations (e.g., fee collection).
 */
interface IVaultExplorer {
    /***************************************************************************
                                  Vault Contracts
    ***************************************************************************/

    /**
     * @notice Returns the main Vault address.
     * @dev The main Vault contains the entrypoint and main liquidity operation implementations.
     * @return vault The address of the main Vault contract
     */
    function getVault() external view returns (address);

    /**
     * @notice Returns the VaultExtension contract address.
     * @dev Function is in the main Vault contract. The VaultExtension handles less critical or frequently used
     * functions, since delegate calls through the Vault are more expensive than direct calls. The main Vault
     * contains the core code for swaps and liquidity operations.
     *
     * @return vaultExtension Address of the VaultExtension
     */
    function getVaultExtension() external view returns (address);

    /**
     * @notice Returns the VaultAdmin contract address.
     * @dev The VaultAdmin contract mostly implements permissioned functions.
     * @return vaultAdmin The address of the Vault admin
     */
    function getVaultAdmin() external view returns (address);

    /**
     * @notice Returns the Authorizer address.
     * @dev The authorizer holds the permissions granted by governance. It is set on Vault deployment, and can
     * be changed through a permissioned call. Being in the main Vault contract saves gas on every permissioned call.
     *
     * @return authorizer Address of the authorizer contract
     */
    function getAuthorizer() external view returns (address);

    /**
     * @notice Returns the Protocol Fee Controller address.
     * @return protocolFeeController Address of the ProtocolFeeController
     */
    function getProtocolFeeController() external view returns (address);

    /*******************************************************************************
                              Transient Accounting
    *******************************************************************************/

    /**
     * @notice Returns whether the Vault is unlocked (i.e., executing an operation).
     * @dev The Vault must be unlocked to perform state-changing liquidity operations.
     * @return unlocked True if the Vault is unlocked, false otherwise
     */
    function isUnlocked() external view returns (bool);

    /**
     *  @notice Returns the count of non-zero deltas.
     *  @return nonzeroDeltaCount The current value of `_nonzeroDeltaCount`
     */
    function getNonzeroDeltaCount() external view returns (uint256);

    /**
     * @notice Retrieves the token delta for a specific token.
     * @dev This function allows reading the value from the `_tokenDeltas` mapping.
     * @param token The token for which the delta is being fetched
     * @return tokenDelta The delta of the specified token
     */
    function getTokenDelta(IERC20 token) external view returns (int256);

    /**
     * @notice Retrieves the reserve (i.e., total Vault balance) of a given token.
     * @param token The token for which to retrieve the reserve
     * @return reserveAmount The amount of reserves for the given token
     */
    function getReservesOf(IERC20 token) external view returns (uint256);

    /*******************************************************************************
                                    Pool Registration
    *******************************************************************************/

    /**
     * @notice Checks whether a pool is registered.
     * @param pool Address of the pool to check
     * @return registered True if the pool is registered, false otherwise
     */
    function isPoolRegistered(address pool) external view returns (bool);

    /*******************************************************************************
                                    Pool Information
    *******************************************************************************/

    /**
     * @notice Checks whether a pool is initialized.
     * @dev An initialized pool can be considered registered as well.
     * @param pool Address of the pool to check
     * @return initialized True if the pool is initialized, false otherwise
     */
    function isPoolInitialized(address pool) external view returns (bool);

    /**
     * @notice Gets the tokens registered to a pool.
     * @param pool Address of the pool
     * @return tokens List of tokens in the pool
     */
    function getPoolTokens(address pool) external view returns (IERC20[] memory);

    /**
     * @notice Gets the index of a token in a given pool.
     * @dev Reverts if the pool is not registered, or if the token does not belong to the pool.
     * Function is in the main Vault contract.
     *
     * @param pool Address of the pool
     * @param token Address of the token
     * @return tokenCount Number of tokens in the pool
     * @return index Index corresponding to the given token in the pool's token list
     */
    function getPoolTokenCountAndIndexOfToken(address pool, IERC20 token) external view returns (uint256, uint256);

    /**
     * @notice Gets pool token rates.
     * @dev This function performs external calls if tokens are yield-bearing. All returned arrays are in token
     * registration order.
     *
     * @param pool Address of the pool
     * @return decimalScalingFactors Token decimal scaling factors
     * @return tokenRates Token rates for yield-bearing tokens, or FP(1) for standard tokens
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
    function getPoolData(address pool) external view returns (PoolData memory);

    /**
     * @notice Gets the raw data for a pool: tokens, raw balances, scaling factors.
     * @param pool Address of the pool
     * @return tokens The pool tokens, sorted in registration order
     * @return tokenInfo Token info, sorted in token registration order
     * @return balancesRaw Raw balances, sorted in token registration order
     * @return lastLiveBalances Last saved live balances, sorted in token registration order
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
            uint256[] memory lastLiveBalances
        );

    /**
     * @notice Gets current live balances of a given pool (fixed-point, 18 decimals), corresponding to its tokens in
     * registration order.
     *
     * @param pool Address of the pool
     * @return balancesLiveScaled18  Token balances after paying yield fees, applying decimal scaling and rates
     */
    function getCurrentLiveBalances(address pool) external view returns (uint256[] memory balancesLiveScaled18);

    /**
     * @notice Gets the configuration parameters of a pool.
     * @dev The `PoolConfig` contains liquidity management and other state flags, fee percentages, the pause window.
     * @param pool Address of the pool
     * @return poolConfig The pool configuration as a `PoolConfig` struct
     */
    function getPoolConfig(address pool) external view returns (PoolConfig memory);

    /**
     * @notice Gets the hooks configuration parameters of a pool.
     * @dev The `HooksConfig` contains flags indicating which pool hooks are implemented.
     * @param pool Address of the pool
     * @return hooksConfig The hooks configuration as a `HooksConfig` struct
     */
    function getHooksConfig(address pool) external view returns (HooksConfig memory);

    /**
     * @notice Gets the current bpt rate of a pool, by dividing the current invariant by the total supply of BPT.
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
    function balanceOf(address token, address account) external view returns (uint256);

    /**
     * @notice Gets the allowance of a spender for a given ERC20 token and owner.
     * @param token Address of the token
     * @param owner Address of the owner
     * @param spender Address of the spender
     * @return allowance Amount of tokens the spender is allowed to spend
     */
    function allowance(address token, address owner, address spender) external view returns (uint256);

    /*******************************************************************************
                                    Pool Pausing
    *******************************************************************************/

    /**
     * @notice Indicates whether a pool is paused.
     * @dev If a pool is paused, all non-Recovery Mode state-changing operations will revert.
     * @param pool The pool to be checked
     * @return paused True if the pool is paused
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
     * @return swapFeeAmount The total amount of fees accumulated in the specified token
     */
    function getAggregateSwapFeeAmount(address pool, IERC20 token) external view returns (uint256);

    /**
     * @notice Returns the accumulated yield fees (including aggregate fees) in `token` collected by the pool.
     * @param pool The address of the pool for which aggregate fees have been collected
     * @param token The address of the token in which fees have been accumulated
     * @return yieldFeeAmount The total amount of fees accumulated in the specified token
     */
    function getAggregateYieldFeeAmount(address pool, IERC20 token) external view returns (uint256);

    /**
     * @notice Fetches the static swap fee percentage for a given pool.
     * @param pool The address of the pool whose static swap fee percentage is being queried
     * @return swapFeePercentage The current static swap fee percentage for the specified pool
     */
    function getStaticSwapFeePercentage(address pool) external view returns (uint256);

    /**
     * @notice Fetches the role accounts for a given pool (pause manager, swap manager, pool creator)
     * @param pool The address of the pool whose roles are being queried
     * @return roleAccounts A struct containing the role accounts for the pool (or 0 if unassigned)
     */
    function getPoolRoleAccounts(address pool) external view returns (PoolRoleAccounts memory);

    /**
     * @notice Query the current dynamic swap fee of a pool, given a set of swap parameters.
     * @dev Reverts if the hook doesn't return the success flag set to `true`.
     * @param pool The pool
     * @param swapParams The swap parameters used to compute the fee
     * @return dynamicSwapFeePercentage The dynamic swap fee percentage
     */
    function computeDynamicSwapFeePercentage(
        address pool,
        PoolSwapParams memory swapParams
    ) external view returns (uint256);

    /*******************************************************************************
                                    Recovery Mode
    *******************************************************************************/

    /**
     * @notice Checks whether a pool is in Recovery Mode.
     * @dev Recovery Mode enables a safe proportional withdrawal path, with no external calls.
     * @param pool Address of the pool to check
     * @return recoveryMode True if the pool is in Recovery Mode, false otherwise
     */
    function isPoolInRecoveryMode(address pool) external view returns (bool);

    /*******************************************************************************
                                    Queries
    *******************************************************************************/

    /**
     * @notice Checks if the queries enabled on the Vault.
     * @dev This is a one-way switch. Once queries are disabled, they can never be re-enabled.
     * The query functions rely on a specific EVM feature to detect static calls. Query operations are exempt from
     * settlement constraints, so it's critical that no state changes can occur. We retain the ability to disable
     * queries in the unlikely event that EVM changes violate its assumptions (perhaps on an L2).
     *
     * @return queryDisabled If true, then queries are disabled
     */
    function isQueryDisabled() external view returns (bool);

    /***************************************************************************
                              Vault Admin Functions
    ***************************************************************************/

    /**
     * @notice Returns the Vault's pause window end time.
     * @dev This value is immutable, and represents the timestamp after which the Vault can no longer be paused
     * by governance.
     *
     * @return pauseWindowEndTime The timestamp when the Vault's pause window ends
     */
    function getPauseWindowEndTime() external view returns (uint32);

    /**
     * @notice Returns the Vault's buffer period duration.
     * @dev This value is immutable. It represents the period during which, if paused, the Vault will remain paused.
     * This ensures there is time available to address whatever issue caused the Vault to be paused.
     *
     * @return bufferPeriodDuration The length of the buffer period in seconds
     */
    function getBufferPeriodDuration() external view returns (uint32);

    /**
     * @notice Returns the Vault's buffer period end time.
     * @dev This value is immutable. If already paused, the Vault can be unpaused until this timestamp.
     * @return bufferPeriodEndTime The timestamp after which the Vault remains permanently unpaused
     */
    function getBufferPeriodEndTime() external view returns (uint32);

    /**
     * @notice Get the minimum number of tokens in a pool.
     * @dev We expect the vast majority of pools to be 2-token.
     * @return minTokens The minimum token count of a pool
     */
    function getMinimumPoolTokens() external view returns (uint256);

    /**
     * @notice Get the maximum number of tokens in a pool.
     * @return maxTokens The maximum token count of a pool
     */
    function getMaximumPoolTokens() external view returns (uint256);

    /**
     * @notice Get the minimum trade amount in a pool operation.
     * @dev This limit is applied to the 18-decimal "upscaled" amount in any operation (swap, add/remove liquidity).
     * @return minimumTradeAmount The minimum trade amount as an 18-decimal floating point number
     */
    function getMinimumTradeAmount() external view returns (uint256);

    /**
     * @notice Get the minimum amount that can be wrapped by an ERC4626 token buffer by the Vault.
     * @dev This limit is applied to native decimal values, and guards against rounding errors.
     * @return minimumWrapAmount The minimum wrap amount
     */
    function getMinimumWrapAmount() external view returns (uint256);

    /**
     * @notice Get the minimum total supply of pool tokens (BPT) for an initialized pool.
     * @dev This prevents pools from being completely drained. When the pool is initialized, this minimum amount of BPT
     * is minted to the zero address. This is an 18-decimal floating point number; BPT are always 18 decimals.
     *
     * @return minimumTotalSupply The minimum total supply a pool can have after initialization
     */
    function getPoolMinimumTotalSupply() external view returns (uint256);

    /**
     * @notice Get the minimum total supply of an ERC4626 wrapped token buffer in the Vault.
     * @dev This prevents buffers from being completely drained. When the buffer is initialized, this minimum number
     * of shares is added to the shares resulting from the initial deposit. Buffer total supply accounting is internal
     * to the Vault, as buffers are not tokenized.
     *
     * @return minimumTotalSupply The minimum total supply a buffer can have after initialization
     */
    function getBufferMinimumTotalSupply() external view returns (uint256);

    /*******************************************************************************
                                    Vault Pausing
    *******************************************************************************/

    /**
     * @notice Indicates whether the Vault is paused.
     * @dev If the Vault is paused, all non-Recovery Mode state-changing operations will revert.
     * @return paused True if the Vault is paused
     */
    function isVaultPaused() external view returns (bool);

    /**
     * @notice Returns the paused status, and end times of the Vault's pause window and buffer period.
     * @return paused True if the Vault is paused
     * @return vaultPauseWindowEndTime The timestamp of the end of the Vault's pause window
     * @return vaultBufferPeriodEndTime The timestamp of the end of the Vault's buffer period
     */
    function getVaultPausedState() external view returns (bool, uint32, uint32);

    /*******************************************************************************
                                   Fees
    *******************************************************************************/

    /**
     * @notice Gets the aggregate swap and yield fee percentages for a pool.
     * @dev These are determined by the current protocol and pool creator fees, set in the `ProtocolFeeController`.
     * These data are accessible as part of the `PoolConfig` (accessible through `getPoolConfig`), and also through
     * the `IPoolInfo` on the pool itself. Standard Balancer pools implement this interface, but custom pools are not
     * required to. We add this as a convenience function with the same interface, but it will fetch from the Vault
     * directly to ensure it is always supported.
     *
     * @param pool Address of the pool
     * @return aggregateSwapFeePercentage The aggregate percentage fee applied to swaps
     * @return aggregateYieldFeePercentage The aggregate percentage fee applied to yield
     */
    function getAggregateFeePercentages(
        address pool
    ) external view returns (uint256 aggregateSwapFeePercentage, uint256 aggregateYieldFeePercentage);

    /**
     * @notice Collects accumulated aggregate swap and yield fees for the specified pool.
     * @dev Fees are sent to the ProtocolFeeController address.
     * @param pool The pool on which all aggregate fees should be collected
     */
    function collectAggregateFees(address pool) external;

    /*******************************************************************************
                                  ERC4626 Buffers
    *******************************************************************************/

    /**
     * @notice Indicates whether the Vault buffers are paused.
     * @dev When buffers are paused, all buffer operations (i.e., calls on the Router with `isBuffer` true)
     * will revert. This operation is reversible.
     *
     * @return buffersPaused True if the Vault buffers are paused
     */
    function areBuffersPaused() external view returns (bool);

    /**
     * @notice Returns the asset registered for a given wrapped token.
     * @dev The asset can never change after buffer initialization.
     * @param wrappedToken Address of the wrapped token that implements IERC4626
     * @return underlyingToken Address of the underlying token registered for the wrapper; `address(0)` if the buffer
     * has not been initialized.
     */
    function getBufferAsset(IERC4626 wrappedToken) external view returns (address underlyingToken);

    /**
     * @notice Returns the shares (internal buffer BPT) of a liquidity owner: a user that deposited assets
     * in the buffer.
     *
     * @param wrappedToken Address of the wrapped token that implements IERC4626
     * @param liquidityOwner Address of the user that owns liquidity in the wrapped token's buffer
     * @return ownerShares Amount of shares allocated to the liquidity owner, in native underlying token decimals
     */
    function getBufferOwnerShares(
        IERC4626 wrappedToken,
        address liquidityOwner
    ) external view returns (uint256 ownerShares);

    /**
     * @notice Returns the supply shares (internal buffer BPT) of the ERC4626 buffer.
     * @param wrappedToken Address of the wrapped token that implements IERC4626
     * @return bufferShares Amount of supply shares of the buffer, in native underlying token decimals
     */
    function getBufferTotalShares(IERC4626 wrappedToken) external view returns (uint256 bufferShares);

    /**
     * @notice Returns the amount of underlying and wrapped tokens deposited in the internal buffer of the Vault.
     * @param wrappedToken Address of the wrapped token that implements IERC4626
     * @return underlyingBalanceRaw Amount of underlying tokens deposited into the buffer, in native token decimals
     * @return wrappedBalanceRaw Amount of wrapped tokens deposited into the buffer, in native token decimals
     */
    function getBufferBalance(
        IERC4626 wrappedToken
    ) external view returns (uint256 underlyingBalanceRaw, uint256 wrappedBalanceRaw);
}
