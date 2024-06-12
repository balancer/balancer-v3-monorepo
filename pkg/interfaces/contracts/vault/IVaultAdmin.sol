// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { IProtocolFeeController } from "./IProtocolFeeController.sol";
import { IAuthorizer } from "./IAuthorizer.sol";
import { IVault } from "./IVault.sol";

interface IVaultAdmin {
    /*******************************************************************************
                              Constants and immutables
    *******************************************************************************/

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
    function getMinimumPoolTokens() external pure returns (uint256);

    /**
     * @notice Get the maximum number of tokens in a pool.
     * @return The token count of a minimal pool
     */
    function getMaximumPoolTokens() external pure returns (uint256);

    /// @dev Returns the main Vault address.
    function vault() external view returns (IVault);

    /*******************************************************************************
                                    Pool Information
    *******************************************************************************/

    /**
     * @notice Retrieve the scaling factors from a pool's rate providers.
     * @dev This is not included in `getPoolTokenInfo` since it makes external calls that might revert,
     * effectively preventing retrieval of basic pool parameters. Tokens without rate providers will always return
     * FixedPoint.ONE (1e18).
     */
    function getPoolTokenRates(address pool) external view returns (uint256[] memory);

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

    /**
     * @notice Pause the Vault: an emergency action which disables all operational state-changing functions.
     * @dev This is a permissioned function that will only work during the Pause Window set during deployment.
     */
    function pauseVault() external;

    /**
     * @notice Reverse a `pause` operation, and restore the Vault to normal functionality.
     * @dev This is a permissioned function that will only work on a paused Vault within the Buffer Period set during
     * deployment. Note that the Vault will automatically unpause after the Buffer Period expires.
     */
    function unpauseVault() external;

    /*******************************************************************************
                                    Pool Pausing
    *******************************************************************************/

    /**
     * @notice Pause the Pool: an emergency action which disables all pool functions.
     * @dev This is a permissioned function that will only work during the Pause Window set during pool factory
     * deployment.
     */
    function pausePool(address pool) external;

    /**
     * @notice Reverse a `pause` operation, and restore the Pool to normal functionality.
     * @dev This is a permissioned function that will only work on a paused Pool within the Buffer Period set during
     * deployment. Note that the Pool will automatically unpause after the Buffer Period expires.
     */
    function unpausePool(address pool) external;

    /*******************************************************************************
                                   Fees
    *******************************************************************************/

    /**
     * @notice Assigns a new static swap fee percentage to the specified pool.
     * @dev This is a permissioned function, disabled if the pool is paused. The swap fee percentage must be within
     * the bounds specified by the pool's implementation of `ISwapFeePercentageBounds`.
     * Emits the SwapFeePercentageChanged event.
     *
     * @param pool The address of the pool for which the static swap fee will be changed
     * @param swapFeePercentage The new swap fee percentage to apply to the pool
     */
    function setStaticSwapFeePercentage(address pool, uint256 swapFeePercentage) external;

    /**
     * @notice Collects accumulated protocol swap and yield fees for the specified pool.
     * @dev Fees are sent to the ProtocolFeeController address.
     * @param pool The pool on which all protocol fees should be collected
     */
    function collectProtocolFees(address pool) external;

    /**
     * @notice Update an aggregate swap fee percentage.
     * @dev Can only be called by the current protocol fee controller. Called when governance overrides a protocol fee
     * for a specific pool, or to permissionlessly update a pool to a changed global protocol fee value (if the pool's
     * fee has not previously been set by governance). Ensures the aggregate percentage <= FixedPoint.ONE.
     *
     * @param pool The pool whose fee will be updated
     * @param newAggregateSwapFeePercentage The new aggregate swap fee percentage
     */
    function updateAggregateSwapFeePercentage(address pool, uint256 newAggregateSwapFeePercentage) external;

    /**
     * @notice Update an aggregate yield fee percentage.
     * @dev Can only be called by the current protocol fee controller. Called when governance overrides a protocol fee
     * for a specific pool, or to permissionlessly update a pool to a changed global protocol fee value (if the pool's
     * fee has not previously been set by governance). Ensures the aggregate percentage <= FixedPoint.ONE.
     *
     * @param pool The pool whose fee will be updated
     * @param newAggregateYieldFeePercentage The new aggregate yield fee percentage
     */
    function updateAggregateYieldFeePercentage(address pool, uint256 newAggregateYieldFeePercentage) external;

    /**
     * @notice Sets a new Protocol Fee Controller for the Vault.
     * @dev This is a permissioned call.
     * Emits a `ProtocolFeeControllerChanged` event.
     */
    function setProtocolFeeController(IProtocolFeeController newProtocolFeeController) external;

    /*******************************************************************************
                                    Recovery Mode
    *******************************************************************************/

    /**
     * @notice Enable recovery mode for a pool.
     * @dev This is a permissioned function.
     * @param pool The pool
     */
    function enableRecoveryMode(address pool) external;

    /**
     * @notice Disable recovery mode for a pool.
     * @dev This is a permissioned function.
     * @param pool The pool
     */
    function disableRecoveryMode(address pool) external;

    /*******************************************************************************
                                    Queries
    *******************************************************************************/

    /// @notice Disables queries functionality on the Vault. Can be called only by governance.
    function disableQuery() external;

    /*******************************************************************************
                         Yield-bearing token buffers
    *******************************************************************************/
    /**
     * @notice Unpauses native vault buffers globally. When buffers are paused, it's not possible to add liquidity or
     * wrap/unwrap tokens using Vault's `erc4626BufferWrapOrUnwrap` primitive. However, it's still possible to remove
     * liquidity.
     * @dev This is a permissioned call.
     */
    function unpauseVaultBuffers() external;

    /**
     * @notice Pauses native vault buffers globally. When buffers are paused, it's not possible to add liquidity or
     * wrap/unwrap tokens using Vault's `erc4626BufferWrapOrUnwrap` primitive. However, it's still possible to remove
     * liquidity. Currently it's not possible to pause vault buffers individually.
     * @dev This is a permissioned call.
     */
    function pauseVaultBuffers() external;

    /**
     * @notice Adds liquidity to an yield-bearing token buffer (linear pool embedded in the vault).
     *
     * @param wrappedToken Address of the wrapped token that implements IERC4626
     * @param amountUnderlyingRaw Amount of underlying tokens that will be deposited into the buffer
     * @param amountWrappedRaw Amount of wrapped tokens that will be deposited into the buffer
     * @param sharesOwner Address of contract that will own the deposited liquidity. Only
     *        this contract will be able to remove liquidity from the buffer
     * @return issuedShares the amount of tokens sharesOwner has in the buffer, expressed in underlying token amounts
     *         (it is the BPT of the vault's internal linear pools)
     */
    function addLiquidityToBuffer(
        IERC4626 wrappedToken,
        uint256 amountUnderlyingRaw,
        uint256 amountWrappedRaw,
        address sharesOwner
    ) external returns (uint256 issuedShares);

    /**
     * @notice Removes liquidity from a yield-bearing token buffer (linear pool embedded in the vault).
     * Only proportional exits are supported.
     *
     * Pre-conditions:
     * - sharesOwner is the original msg.sender, it needs to be checked in the router. That's why
     *   this call is authenticated; only routers approved by the DAO can remove the liquidity of a buffer.
     * - The buffer needs to have some liquidity and have its asset registered in `_bufferAssets` storage.
     *
     * @param wrappedToken Address of the wrapped token that implements IERC4626
     * @param sharesToRemove Amount of shares to remove from the buffer. Cannot be greater than sharesOwner
     *        total shares
     * @param sharesOwner Address of contract that owns the deposited liquidity.
     * @return removedUnderlyingBalanceRaw Amount of underlying tokens returned to the user
     * @return removedWrappedBalanceRaw Amount of wrapped tokens returned to the user
     */
    function removeLiquidityFromBuffer(
        IERC4626 wrappedToken,
        uint256 sharesToRemove,
        address sharesOwner
    ) external returns (uint256 removedUnderlyingBalanceRaw, uint256 removedWrappedBalanceRaw);

    /**
     * @notice Returns the shares (internal buffer BPT) of a liquidity owner: a user that deposited assets
     * in the buffer.
     *
     * @param wrappedToken Address of the wrapped token that implements IERC4626
     * @param liquidityOwner Address of the user that owns liquidity in the wrapped token's buffer
     * @return ownerShares Amount of shares allocated to the liquidity owner
     */
    function getBufferOwnerShares(
        IERC20 wrappedToken,
        address liquidityOwner
    ) external view returns (uint256 ownerShares);

    /**
     * @notice Returns the supply shares (internal buffer BPT) of the ERC4626 buffer.
     *
     * @param wrappedToken Address of the wrapped token that implements IERC4626
     * @return bufferShares Amount of supply shares of the buffer
     */
    function getBufferTotalShares(IERC20 wrappedToken) external view returns (uint256 bufferShares);

    /**
     * @notice Returns the amount of underlying and wrapped tokens deposited in the internal buffer of the vault.
     * @param wrappedToken Address of the wrapped token that implements IERC4626
     * @return underlyingBalanceRaw Amount of underlying tokens deposited into the buffer
     * @return wrappedBalanceRaw Amount of wrapped tokens deposited into the buffer
     */
    function getBufferBalance(
        IERC20 wrappedToken
    ) external view returns (uint256 underlyingBalanceRaw, uint256 wrappedBalanceRaw);

    /*******************************************************************************
                                Authentication
    *******************************************************************************/

    /**
     * @notice Sets a new Authorizer for the Vault.
     * @dev This is a permissioned call.
     * Emits an `AuthorizerChanged` event.
     */
    function setAuthorizer(IAuthorizer newAuthorizer) external;
}
