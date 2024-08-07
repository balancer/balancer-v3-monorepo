// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { TokenInfo, PoolRoleAccounts, PoolData, PoolConfig, PoolSwapParams, HooksConfig } from "./VaultTypes.sol";

interface IVaultExplorer {
    /***************************************************************************
                                  Vault Contracts
    ***************************************************************************/

    /**
     * @notice Get the Balancer Vault contract address.
     * @return The address of the Vault
     */
    function getVault() external view returns (address);

    /**
     * @notice Returns the Vault Extension contract address.
     * @dev Function is in the main Vault contract. The VaultExtension handles most permissioned calls, and other
     * functions less frequently used, as delegate calls through the Vault are more expensive than direct calls.
     * The Vault itself contains the core code for swaps and liquidity operations.
     *
     * @return Address of the VaultExtension
     */
    function getVaultExtension() external view returns (address);

    /**
     * @notice Get the Vault Admin contract address.
     * @return Address of the VaultAdmin
     */
    function getVaultAdmin() external view returns (address);

    /**
     * @notice Returns the Vault's Authorizer.
     * @dev Function is in the main Vault contract to save gas on all permissioned calls.
     * @return Address of the authorizer
     */
    function getAuthorizer() external view returns (address);

    /**
     * @notice Returns the Protocol Fee Controller address.
     * @return Address of the ProtocolFeeController
     */
    function getProtocolFeeController() external view returns (address);

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
     * @notice Checks whether a pool is registered.
     * @param pool Address of the pool to check
     * @return True if the pool is registered, false otherwise
     */
    function isPoolRegistered(address pool) external view returns (bool);

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

    /// @notice Returns pool data for a given pool.
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
     * @notice Gets the current bpt rate of a pool, by dividing the current invariant by the total supply of BPT.
     * @param pool Address of the pool
     * @return rate BPT rate
     */
    function getBptRate(address pool) external view returns (uint256 rate);

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
     * @notice Query the current dynamic swap fee of a pool, given a set of swap parameters.
     * @param pool The pool
     * @param swapParams The swap parameters used to compute the fee
     * @return success True if the pool has a dynamic swap fee and it can be successfully computed
     * @return dynamicSwapFee The dynamic swap fee percentage
     */
    function computeDynamicSwapFeePercentage(
        address pool,
        PoolSwapParams memory swapParams
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

    /*******************************************************************************
                                    Queries
    *******************************************************************************/

    /**
     * @notice Checks if the queries enabled on the Vault.
     * @return If true, then queries are disabled
     */
    function isQueryDisabled() external view returns (bool);

    /***************************************************************************
                              Vault Admin Functions
    ***************************************************************************/

    /**
     * @notice Returns Vault's pause window end time.
     * @dev This value is immutable; the getter can be called by anyone.
     */
    function getPauseWindowEndTime() external view returns (uint32);

    /**
     * @notice Returns Vault's buffer period duration.
     * @dev This value is immutable; the getter can be called by anyone.
     */
    function getBufferPeriodDuration() external view returns (uint32);

    /**
     * @notice Returns Vault's buffer period end time.
     * @dev This value is immutable; the getter can be called by anyone.
     */
    function getBufferPeriodEndTime() external view returns (uint32);

    /**
     * @notice Get the minimum number of tokens in a pool.
     * @dev We expect the vast majority of pools to be 2-token.
     * @return The token count of a minimal pool
     */
    function getMinimumPoolTokens() external view returns (uint256);

    /**
     * @notice Get the maximum number of tokens in a pool.
     * @return The token count of a minimal pool
     */
    function getMaximumPoolTokens() external view returns (uint256);

    /*******************************************************************************
                                    Vault Pausing
    *******************************************************************************/

    /**
     * @notice Indicates whether the Vault is paused.
     * @return True if the Vault is paused
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
                              Yield-bearing Token Buffers
    *******************************************************************************/

    /**
     * @notice Returns the shares (internal buffer BPT) of a liquidity owner: a user that deposited assets
     * in the buffer.
     *
     * @param wrappedToken Address of the wrapped token that implements IERC4626
     * @param liquidityOwner Address of the user that owns liquidity in the wrapped token's buffer
     * @return ownerShares Amount of shares allocated to the liquidity owner
     */
    function getBufferOwnerShares(
        IERC4626 wrappedToken,
        address liquidityOwner
    ) external view returns (uint256 ownerShares);

    /**
     * @notice Returns the supply shares (internal buffer BPT) of the ERC4626 buffer.
     *
     * @param wrappedToken Address of the wrapped token that implements IERC4626
     * @return bufferShares Amount of supply shares of the buffer
     */
    function getBufferTotalShares(IERC4626 wrappedToken) external view returns (uint256 bufferShares);

    /**
     * @notice Returns the amount of underlying and wrapped tokens deposited in the internal buffer of the vault.
     * @param wrappedToken Address of the wrapped token that implements IERC4626
     * @return underlyingBalanceRaw Amount of underlying tokens deposited into the buffer
     * @return wrappedBalanceRaw Amount of wrapped tokens deposited into the buffer
     */
    function getBufferBalance(
        IERC4626 wrappedToken
    ) external view returns (uint256 underlyingBalanceRaw, uint256 wrappedBalanceRaw);
}
