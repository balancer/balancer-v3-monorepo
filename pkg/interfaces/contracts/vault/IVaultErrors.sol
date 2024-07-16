// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @dev Errors are declared inside an interface (namespace) to improve DX with Typechain.
interface IVaultErrors {
    /*******************************************************************************
                            Registration and Initialization
    *******************************************************************************/

    /**
     * @dev A pool has already been registered. `registerPool` may only be called once.
     * @param pool The already registered pool
     */
    error PoolAlreadyRegistered(address pool);

    /**
     * @dev A pool has already been initialized. `initialize` may only be called once.
     * @param pool The already initialized pool
     */
    error PoolAlreadyInitialized(address pool);

    /**
     * @dev A pool has not been registered.
     * @param pool The unregistered pool
     */
    error PoolNotRegistered(address pool);

    /**
     * @dev A referenced pool has not been initialized.
     * @param pool The uninitialized pool
     */
    error PoolNotInitialized(address pool);

    /**
     * @dev A hook contract rejected a pool on registration.
     * @param poolHooksContract Address of the hook contract that rejected the pool registration
     * @param pool Address of the rejected pool
     * @param poolFactory Address of the pool factory
     */
    error HookRegistrationFailed(address poolHooksContract, address pool, address poolFactory);

    /**
     * @dev A token was already registered (i.e., it is a duplicate in the pool).
     * @param token The duplicate token
     */
    error TokenAlreadyRegistered(IERC20 token);

    /// @dev The token count is below the minimum allowed.
    error MinTokens();

    /// @dev The token count is above the maximum allowed.
    error MaxTokens();

    /// @dev Invalid tokens (e.g., zero) cannot be registered.
    error InvalidToken();

    /// @dev The token type given in a TokenConfig during pool registration is invalid.
    error InvalidTokenType();

    /// @dev The data in a TokenConfig struct is inconsistent or unsupported.
    error InvalidTokenConfiguration();

    /**
     * @dev The token list passed into an operation does not match the pool tokens in the pool.
     * @param pool Address of the pool
     * @param expectedToken The correct token at a given index in the pool
     * @param actualToken The actual token found at that index
     */
    error TokensMismatch(address pool, address expectedToken, address actualToken);

    /*******************************************************************************
                                 Transient Accounting
    *******************************************************************************/

    /// @dev A transient accounting operation completed with outstanding token deltas.
    error BalanceNotSettled();

    /// @dev A user called a Vault function (swap, add/remove liquidity) outside the lock context.
    error VaultIsNotUnlocked();

    /// @dev The pool has returned false to the beforeSwap hook, indicating the transaction should revert.
    error DynamicSwapFeeHookFailed();

    /// @dev The pool has returned false to the beforeSwap hook, indicating the transaction should revert.
    error BeforeSwapHookFailed();

    /// @dev The pool has returned false to the afterSwap hook, indicating the transaction should revert.
    error AfterSwapHookFailed();

    /// @dev The pool has returned false to the beforeInitialize hook, indicating the transaction should revert.
    error BeforeInitializeHookFailed();

    /// @dev The pool has returned false to the afterInitialize hook, indicating the transaction should revert.
    error AfterInitializeHookFailed();

    /// @dev The pool has returned false to the beforeAddLiquidity hook, indicating the transaction should revert.
    error BeforeAddLiquidityHookFailed();

    /// @dev The pool has returned false to the afterAddLiquidity hook, indicating the transaction should revert.
    error AfterAddLiquidityHookFailed();

    /// @dev The pool has returned false to the beforeRemoveLiquidity hook, indicating the transaction should revert.
    error BeforeRemoveLiquidityHookFailed();

    /// @dev The pool has returned false to the afterRemoveLiquidity hook, indicating the transaction should revert.
    error AfterRemoveLiquidityHookFailed();

    /// @dev An unauthorized Router tried to call a permissioned function (i.e., using the Vault's token allowance).
    error RouterNotTrusted();

    /*******************************************************************************
                                        Swaps
    *******************************************************************************/

    /// @dev The user tried to swap zero tokens.
    error AmountGivenZero();

    /// @dev The user attempted to swap a token for itself.
    error CannotSwapSameToken();

    /// @dev The user attempted to operate with a token that is not in the pool.
    error TokenNotRegistered(IERC20 token);

    /// @dev An amount in or out has exceeded the limit specified in the swap request.
    error SwapLimit(uint256 amount, uint256 limit);

    /// @dev A hook adjusted amount in or out has exceeded the limit specified in the swap request.
    error HookAdjustedSwapLimit(uint256 amount, uint256 limit);

    /// @dev The amount given or calculated for an operation is below the minimum limit.
    error TradeAmountTooSmall();

    /*******************************************************************************
                                    Add Liquidity
    *******************************************************************************/

    /// @dev Add liquidity kind not supported.
    error InvalidAddLiquidityKind();

    /// @dev A required amountIn exceeds the maximum limit specified for the operation.
    error AmountInAboveMax(IERC20 token, uint256 amount, uint256 limit);

    /// @dev A hook adjusted amountIn exceeds the maximum limit specified for the operation.
    error HookAdjustedAmountInAboveMax(IERC20 token, uint256 amount, uint256 limit);

    /// @dev The BPT amount received from adding liquidity is below the minimum specified for the operation.
    error BptAmountOutBelowMin(uint256 amount, uint256 limit);

    /// @dev Pool does not support adding liquidity with a customized input.
    error DoesNotSupportAddLiquidityCustom();

    /// @dev Pool does not support adding liquidity through donation.
    error DoesNotSupportDonation();

    /*******************************************************************************
                                    Remove Liquidity
    *******************************************************************************/

    /// @dev Remove liquidity kind not supported.
    error InvalidRemoveLiquidityKind();

    /// @dev The actual amount out is below the minimum limit specified for the operation.
    error AmountOutBelowMin(IERC20 token, uint256 amount, uint256 limit);

    /// @dev The hook adjusted amount out is below the minimum limit specified for the operation.
    error HookAdjustedAmountOutBelowMin(IERC20 token, uint256 amount, uint256 limit);

    /// @dev The required BPT amount in exceeds the maximum limit specified for the operation.
    error BptAmountInAboveMax(uint256 amount, uint256 limit);

    /// @dev Pool does not support removing liquidity with a customized input.
    error DoesNotSupportRemoveLiquidityCustom();

    /*******************************************************************************
                                     Fees
    *******************************************************************************/

    /**
     * @dev Error raised when the sum of the parts (aggregate swap or yield fee)
     * is greater than the whole (total swap or yield fee). Also validated when the protocol fee
     * controller updates aggregate fee percentages in the Vault.
     */
    error ProtocolFeesExceedTotalCollected();

    /**
     * @dev  Error raised when the swap fee percentage is less than the minimum allowed value.
     * The Vault itself does not impose a universal minimum. Rather, it validates against the
     * range specified by the `ISwapFeePercentageBounds` interface. and reverts with this error
     * if it is below the minimum value returned by the pool.
     *
     * Pools with dynamic fees do not check these limits.
     */
    error SwapFeePercentageTooLow();

    /**
     * @dev  Error raised when the swap fee percentage is greater than the maximum allowed value.
     * The Vault itself does not impose a universal minimum. Rather, it validates against the
     * range specified by the `ISwapFeePercentageBounds` interface. and reverts with this error
     * if it is above the maximum value returned by the pool.
     *
     * Pools with dynamic fees do not check these limits.
     */
    error SwapFeePercentageTooHigh();

    /**
     * @dev Primary fee percentages are 18-decimal values, stored here in 64 bits, and calculated with full 256-bit
     * precision. However, the resulting aggregate fees are stored in the Vault with 24-bit precision, which
     * corresponds to 0.00001% resolution (i.e., a fee can be 1%, 1.00001%, 1.00002%, but not 1.000005%).
     * Disallow setting fees such that there would be precision loss in the Vault, leading to a discrepancy between
     * the aggregate fee calculated here and that stored in the Vault.
     */
    error FeePrecisionTooHigh();

    /*******************************************************************************
                                    Queries
    *******************************************************************************/

    /// @dev A user tried to execute a query operation when they were disabled.
    error QueriesDisabled();

    /*******************************************************************************
                                Recovery Mode
    *******************************************************************************/

    /**
     * @dev Cannot enable recovery mode when already enabled.
     * @param pool The pool
     */
    error PoolInRecoveryMode(address pool);

    /**
     * @dev Cannot disable recovery mode when not enabled.
     * @param pool The pool
     */
    error PoolNotInRecoveryMode(address pool);

    /*******************************************************************************
                                Authentication
    *******************************************************************************/

    /**
     * @dev Error indicating the sender is not the Vault (e.g., someone is trying to call a permissioned function).
     * @param sender The account attempting to call a permissioned function
     */
    error SenderIsNotVault(address sender);

    /*******************************************************************************
                                        Pausing
    *******************************************************************************/

    /// @dev The caller specified a pause window period longer than the maximum.
    error VaultPauseWindowDurationTooLarge();

    /// @dev The caller specified a buffer period longer than the maximum.
    error PauseBufferPeriodDurationTooLarge();

    /// @dev A user tried to perform an operation while the Vault was paused.
    error VaultPaused();

    /// @dev Governance tried to unpause the Vault when it was not paused.
    error VaultNotPaused();

    /// @dev Governance tried to pause the Vault after the pause period expired.
    error VaultPauseWindowExpired();

    /**
     * @dev A user tried to perform an operation involving a paused Pool.
     * @param pool The paused pool
     */
    error PoolPaused(address pool);

    /**
     * @dev Governance tried to unpause the Pool when it was not paused.
     * @param pool The unpaused pool
     */
    error PoolNotPaused(address pool);

    /**
     * @dev Governance tried to pause a Pool after the pause period expired.
     * @param pool The pool
     */
    error PoolPauseWindowExpired(address pool);

    /*******************************************************************************
                                    Miscellaneous
    *******************************************************************************/

    /// @dev Optional User Data should be empty in the current add / remove liquidity kind.
    error UserDataNotSupported();

    /// @dev Pool does not support adding / removing liquidity with an unbalanced input.
    error DoesNotSupportUnbalancedLiquidity();

    /// @dev The contract should not receive ETH.
    error CannotReceiveEth();

    /// @dev The Vault extension was called by an account directly; it can only be called by the Vault via delegatecall.
    error NotVaultDelegateCall();

    /// @dev Error thrown when a function is not supported.
    error OperationNotSupported();

    /// @dev The vault extension was configured with an incorrect Vault address.
    error WrongVaultExtensionDeployment();

    /// @dev The protocol fee controller was configured with an incorrect Vault address.
    error WrongProtocolFeeControllerDeployment();

    /// @dev The vault admin was configured with an incorrect Vault address.
    error WrongVaultAdminDeployment();

    /// @dev Quote reverted with a reserved error code.
    error QuoteResultSpoofed();

    /// @dev The user is trying to remove more than their allocated shares from the buffer.
    error NotEnoughBufferShares();

    /// @dev The wrapped token asset does not match the underlying token of the swap path.
    error WrongWrappedTokenAsset(address token);

    /// @dev The wrappedToken wrap/unwrap function did not deposit/return the expected amount of underlying tokens.
    error WrongUnderlyingAmount(address wrappedToken);

    /// @dev The wrappedToken wrap/unwrap function did not burn/mint the expected amount of wrapped tokens.
    error WrongWrappedAmount(address wrappedToken);

    /// @dev The amount given to wrap/unwrap was too small, which can introduce rounding issues.
    error WrapAmountTooSmall(address wrappedToken);

    /// @dev Vault buffers are paused.
    error VaultBuffersArePaused();
}
