// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/// @notice Errors are declared inside an interface (namespace) to improve DX with Typechain.
interface IVaultErrors {
    /*******************************************************************************
                            Registration and Initialization
    *******************************************************************************/

    /**
     * @notice A pool has already been registered. `registerPool` may only be called once.
     * @param pool The already registered pool
     */
    error PoolAlreadyRegistered(address pool);

    /**
     * @notice A pool has already been initialized. `initialize` may only be called once.
     * @param pool The already initialized pool
     */
    error PoolAlreadyInitialized(address pool);

    /**
     * @notice A pool has not been registered.
     * @param pool The unregistered pool
     */
    error PoolNotRegistered(address pool);

    /**
     * @notice A referenced pool has not been initialized.
     * @param pool The uninitialized pool
     */
    error PoolNotInitialized(address pool);

    /**
     * @notice A hook contract rejected a pool on registration.
     * @param poolHooksContract Address of the hook contract that rejected the pool registration
     * @param pool Address of the rejected pool
     * @param poolFactory Address of the pool factory
     */
    error HookRegistrationFailed(address poolHooksContract, address pool, address poolFactory);

    /**
     * @notice A token was already registered (i.e., it is a duplicate in the pool).
     * @param token The duplicate token
     */
    error TokenAlreadyRegistered(IERC20 token);

    /// @notice The token count is below the minimum allowed.
    error MinTokens();

    /// @notice The token count is above the maximum allowed.
    error MaxTokens();

    /// @notice Invalid tokens (e.g., zero) cannot be registered.
    error InvalidToken();

    /// @notice The token type given in a TokenConfig during pool registration is invalid.
    error InvalidTokenType();

    /// @notice The data in a TokenConfig struct is inconsistent or unsupported.
    error InvalidTokenConfiguration();

    /// @notice Tokens with more than 18 decimals are not supported.
    error InvalidTokenDecimals();

    /**
     * @notice The token list passed into an operation does not match the pool tokens in the pool.
     * @param pool Address of the pool
     * @param expectedToken The correct token at a given index in the pool
     * @param actualToken The actual token found at that index
     */
    error TokensMismatch(address pool, address expectedToken, address actualToken);

    /*******************************************************************************
                                 Transient Accounting
    *******************************************************************************/

    /// @notice A transient accounting operation completed with outstanding token deltas.
    error BalanceNotSettled();

    /// @notice A user called a Vault function (swap, add/remove liquidity) outside the lock context.
    error VaultIsNotUnlocked();

    /// @notice The pool has returned false to the beforeSwap hook, indicating the transaction should revert.
    error DynamicSwapFeeHookFailed();

    /// @notice The pool has returned false to the beforeSwap hook, indicating the transaction should revert.
    error BeforeSwapHookFailed();

    /// @notice The pool has returned false to the afterSwap hook, indicating the transaction should revert.
    error AfterSwapHookFailed();

    /// @notice The pool has returned false to the beforeInitialize hook, indicating the transaction should revert.
    error BeforeInitializeHookFailed();

    /// @notice The pool has returned false to the afterInitialize hook, indicating the transaction should revert.
    error AfterInitializeHookFailed();

    /// @notice The pool has returned false to the beforeAddLiquidity hook, indicating the transaction should revert.
    error BeforeAddLiquidityHookFailed();

    /// @notice The pool has returned false to the afterAddLiquidity hook, indicating the transaction should revert.
    error AfterAddLiquidityHookFailed();

    /// @notice The pool has returned false to the beforeRemoveLiquidity hook, indicating the transaction should revert.
    error BeforeRemoveLiquidityHookFailed();

    /// @notice The pool has returned false to the afterRemoveLiquidity hook, indicating the transaction should revert.
    error AfterRemoveLiquidityHookFailed();

    /// @notice An unauthorized Router tried to call a permissioned function (i.e., using the Vault's token allowance).
    error RouterNotTrusted();

    /*******************************************************************************
                                        Swaps
    *******************************************************************************/

    /// @notice The user tried to swap zero tokens.
    error AmountGivenZero();

    /// @notice The user attempted to swap a token for itself.
    error CannotSwapSameToken();

    /**
     * @notice The user attempted to operate with a token that is not in the pool.
     * @param token The unregistered token
     */
    error TokenNotRegistered(IERC20 token);

    /**
     * @notice An amount in or out has exceeded the limit specified in the swap request.
     * @param amount The total amount in or out
     * @param limit The amount of the limit that has been exceeded
     */
    error SwapLimit(uint256 amount, uint256 limit);

    /**
     * @notice A hook adjusted amount in or out has exceeded the limit specified in the swap request.
     * @param amount The total amount in or out
     * @param limit The amount of the limit that has been exceeded
     */
    error HookAdjustedSwapLimit(uint256 amount, uint256 limit);

    /// @notice The amount given or calculated for an operation is below the minimum limit.
    error TradeAmountTooSmall();

    /*******************************************************************************
                                    Add Liquidity
    *******************************************************************************/

    /// @notice Add liquidity kind not supported.
    error InvalidAddLiquidityKind();

    /**
     * @notice A required amountIn exceeds the maximum limit specified for the operation.
     * @param tokenIn The incoming token
     * @param amountIn The total token amount in
     * @param maxAmountIn The amount of the limit that has been exceeded
     */
    error AmountInAboveMax(IERC20 tokenIn, uint256 amountIn, uint256 maxAmountIn);

    /**
     * @notice A hook adjusted amountIn exceeds the maximum limit specified for the operation.
     * @param tokenIn The incoming token
     * @param amountIn The total token amount in
     * @param maxAmountIn The amount of the limit that has been exceeded
     */
    error HookAdjustedAmountInAboveMax(IERC20 tokenIn, uint256 amountIn, uint256 maxAmountIn);

    /**
     * @notice The BPT amount received from adding liquidity is below the minimum specified for the operation.
     * @param amountOut The total BPT amount out
     * @param minAmountOut The amount of the limit that has been exceeded
     */
    error BptAmountOutBelowMin(uint256 amountOut, uint256 minAmountOut);

    /// @notice Pool does not support adding liquidity with a customized input.
    error DoesNotSupportAddLiquidityCustom();

    /// @notice Pool does not support adding liquidity through donation.
    error DoesNotSupportDonation();

    /*******************************************************************************
                                    Remove Liquidity
    *******************************************************************************/

    /// @notice Remove liquidity kind not supported.
    error InvalidRemoveLiquidityKind();

    /**
     * @notice The actual amount out is below the minimum limit specified for the operation.
     * @param tokenOut The outgoing token
     * @param amountOut The total BPT amount out
     * @param minAmountOut The amount of the limit that has been exceeded
     */
    error AmountOutBelowMin(IERC20 tokenOut, uint256 amountOut, uint256 minAmountOut);

    /**
     * @notice The hook adjusted amount out is below the minimum limit specified for the operation.
     * @param tokenOut The outgoing token
     * @param amountOut The total BPT amount out
     * @param minAmountOut The amount of the limit that has been exceeded
     */
    error HookAdjustedAmountOutBelowMin(IERC20 tokenOut, uint256 amountOut, uint256 minAmountOut);

    /**
     * @notice The required BPT amount in exceeds the maximum limit specified for the operation.
     * @param amountIn The total BPT amount in
     * @param maxAmountIn The amount of the limit that has been exceeded
     */
    error BptAmountInAboveMax(uint256 amountIn, uint256 maxAmountIn);

    /// @notice Pool does not support removing liquidity with a customized input.
    error DoesNotSupportRemoveLiquidityCustom();

    /*******************************************************************************
                                     Fees
    *******************************************************************************/

    /**
     * @notice Error raised when there is an overflow in the fee calculation.
     * @dev This occurs when the sum of the parts (aggregate swap or yield fee) is greater than the whole
     * (total swap or yield fee). Also validated when the protocol fee controller updates aggregate fee
     * percentages in the Vault.
     */
    error ProtocolFeesExceedTotalCollected();

    /**
     * @notice Error raised when the swap fee percentage is less than the minimum allowed value.
     * @dev The Vault itself does not impose a universal minimum. Rather, it validates against the
     * range specified by the `ISwapFeePercentageBounds` interface. and reverts with this error
     * if it is below the minimum value returned by the pool.
     *
     * Pools with dynamic fees do not check these limits.
     */
    error SwapFeePercentageTooLow();

    /**
     * @notice Error raised when the swap fee percentage is greater than the maximum allowed value.
     * @dev The Vault itself does not impose a universal minimum. Rather, it validates against the
     * range specified by the `ISwapFeePercentageBounds` interface. and reverts with this error
     * if it is above the maximum value returned by the pool.
     *
     * Pools with dynamic fees do not check these limits.
     */
    error SwapFeePercentageTooHigh();

    /**
     * @notice Primary fee percentages result in an aggregate fee that cannot be stored with the required precision.
     * @dev Primary fee percentages are 18-decimal values, stored here in 64 bits, and calculated with full 256-bit
     * precision. However, the resulting aggregate fees are stored in the Vault with 24-bit precision, which
     * corresponds to 0.00001% resolution (i.e., a fee can be 1%, 1.00001%, 1.00002%, but not 1.000005%).
     * Disallow setting fees such that there would be precision loss in the Vault, leading to a discrepancy between
     * the aggregate fee calculated here and that stored in the Vault.
     */
    error FeePrecisionTooHigh();

    /**
     * @notice A given percentage is above the maximum (usually FixedPoint.ONE, or 1e18 wei).
     * @dev Providing the value might be helpful for debugging.
     */
    error PercentageAboveMax();

    /*******************************************************************************
                                    Queries
    *******************************************************************************/

    /// @notice A user tried to execute a query operation when they were disabled.
    error QueriesDisabled();

    /// @notice An admin tried to re-enable queries, but they were disabled permanently.
    error QueriesDisabledPermanently();

    /*******************************************************************************
                                Recovery Mode
    *******************************************************************************/

    /**
     * @notice Cannot enable recovery mode when already enabled.
     * @param pool The pool
     */
    error PoolInRecoveryMode(address pool);

    /**
     * @notice Cannot disable recovery mode when not enabled.
     * @param pool The pool
     */
    error PoolNotInRecoveryMode(address pool);

    /*******************************************************************************
                                Authentication
    *******************************************************************************/

    /**
     * @notice Error indicating the sender is not the Vault (e.g., someone is trying to call a permissioned function).
     * @param sender The account attempting to call a permissioned function
     */
    error SenderIsNotVault(address sender);

    /*******************************************************************************
                                        Pausing
    *******************************************************************************/

    /// @notice The caller specified a pause window period longer than the maximum.
    error VaultPauseWindowDurationTooLarge();

    /// @notice The caller specified a buffer period longer than the maximum.
    error PauseBufferPeriodDurationTooLarge();

    /// @notice A user tried to perform an operation while the Vault was paused.
    error VaultPaused();

    /// @notice Governance tried to unpause the Vault when it was not paused.
    error VaultNotPaused();

    /// @notice Governance tried to pause the Vault after the pause period expired.
    error VaultPauseWindowExpired();

    /**
     * @notice A user tried to perform an operation involving a paused Pool.
     * @param pool The paused pool
     */
    error PoolPaused(address pool);

    /**
     * @notice Governance tried to unpause the Pool when it was not paused.
     * @param pool The unpaused pool
     */
    error PoolNotPaused(address pool);

    /**
     * @notice Governance tried to pause a Pool after the pause period expired.
     * @param pool The pool
     */
    error PoolPauseWindowExpired(address pool);

    /*******************************************************************************
                                ERC4626 token buffers
    *******************************************************************************/

    /**
     * @notice The buffer for the given wrapped token was already initialized.
     * @param wrappedToken The wrapped token corresponding to the buffer
     */
    error BufferAlreadyInitialized(IERC4626 wrappedToken);

    /**
     * @notice The buffer for the given wrapped token was not initialized.
     * @param wrappedToken The wrapped token corresponding to the buffer
     */
    error BufferNotInitialized(IERC4626 wrappedToken);

    /// @notice The user is trying to remove more than their allocated shares from the buffer.
    error NotEnoughBufferShares();

    /**
     * @notice The wrapped token asset does not match the underlying token.
     * @dev This should never happen, but a malicious wrapper contract might not return the correct address.
     * Legitimate wrapper contracts should make the asset a constant or immutable value.
     *
     * @param wrappedToken The wrapped token corresponding to the buffer
     * @param underlyingToken The underlying token returned by `asset`
     */
    error WrongUnderlyingToken(IERC4626 wrappedToken, address underlyingToken);

    /**
     * @notice A wrapped token reported the zero address as its underlying token asset.
     * @dev This should never happen, but a malicious wrapper contract might do this (e.g., in an attempt to
     * re-initialize the buffer).
     *
     * @param wrappedToken The wrapped token corresponding to the buffer
     */
    error InvalidUnderlyingToken(IERC4626 wrappedToken);

    /**
     * @notice The amount given to wrap/unwrap was too small, which can introduce rounding issues.
     * @param wrappedToken The wrapped token corresponding to the buffer
     */
    error WrapAmountTooSmall(IERC4626 wrappedToken);

    /// @notice Buffer operation attempted while vault buffers are paused.
    error VaultBuffersArePaused();

    /// @notice Buffer shares were minted to the zero address.
    error BufferSharesInvalidReceiver();

    /// @notice Buffer shares were burned from the zero address.
    error BufferSharesInvalidOwner();

    /**
     * @notice The total supply of a buffer can't be lower than the absolute minimum.
     * @param totalSupply The total supply value that was below the minimum
     */
    error BufferTotalSupplyTooLow(uint256 totalSupply);

    /// @dev A wrap/unwrap operation consumed more or returned less underlying tokens than it should.
    error NotEnoughUnderlying(IERC4626 wrappedToken, uint256 expectedUnderlyingAmount, uint256 actualUnderlyingAmount);

    /// @dev A wrap/unwrap operation consumed more or returned less wrapped tokens than it should.
    error NotEnoughWrapped(IERC4626 wrappedToken, uint256 expectedWrappedAmount, uint256 actualWrappedAmount);

    /// @dev Issues shared during initialization are below the requested amount.
    error IssuedSharesBelowMin(uint256 issuedShares, uint256 minIssuedShares);

    /*******************************************************************************
                                    Miscellaneous
    *******************************************************************************/

    /// @notice Pool does not support adding / removing liquidity with an unbalanced input.
    error DoesNotSupportUnbalancedLiquidity();

    /// @notice The contract should not receive ETH.
    error CannotReceiveEth();

    /**
     * @notice The `VaultExtension` contract was called by an account directly.
     * @dev It can only be called by the Vault via delegatecall.
     */
    error NotVaultDelegateCall();

    /// @notice The `VaultExtension` contract was configured with an incorrect Vault address.
    error WrongVaultExtensionDeployment();

    /// @notice The `ProtocolFeeController` contract was configured with an incorrect Vault address.
    error WrongProtocolFeeControllerDeployment();

    /// @notice The `VaultAdmin` contract was configured with an incorrect Vault address.
    error WrongVaultAdminDeployment();

    /// @notice Quote reverted with a reserved error code.
    error QuoteResultSpoofed();
}
