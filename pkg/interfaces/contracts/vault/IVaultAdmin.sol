// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

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
    function getPauseWindowEndTime() external view returns (uint256);

    /**
     * @notice Returns Vault's buffer period duration.
     * @dev This value is immutable; the getter can be called by anyone.
     */
    function getBufferPeriodDuration() external view returns (uint256);

    /**
     * @notice Returns Vault's buffer period end time.
     * @dev This value is immutable; the getter can be called by anyone.
     */
    function getBufferPeriodEndTime() external view returns (uint256);

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
    function getVaultPausedState() external view returns (bool, uint256, uint256);

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
     * @notice Sets a new swap fee percentage for the protocol.
     * @param newSwapFeePercentage The new swap fee percentage to be set
     */
    function setProtocolSwapFeePercentage(uint256 newSwapFeePercentage) external;

    /**
     * @notice Sets a new yield fee percentage for the protocol.
     * @param newYieldFeePercentage The new swap fee percentage to be set
     */
    function setProtocolYieldFeePercentage(uint256 newYieldFeePercentage) external;

    /**
     * @notice Assigns a new static swap fee percentage to the specified pool.
     * @param pool The address of the pool for which the static swap fee will be changed
     * @param swapFeePercentage The new swap fee percentage to apply to the pool
     */
    function setStaticSwapFeePercentage(address pool, uint256 swapFeePercentage) external;

    /**
     * @notice Assigns a new pool creator fee percentage to the specified pool.
     * @param pool The address of the pool for which the pool creator fee will be changed
     * @param poolCreatorFeePercentage The new pool creator fee percentage to apply to the pool
     */
    function setPoolCreatorFeePercentage(address pool, uint256 poolCreatorFeePercentage) external;

    /**
     * @notice Collects accumulated protocol fees for the specified array of tokens.
     * @dev Fees are sent to msg.sender.
     * @param tokens An array of token addresses for which the fees should be collected
     */
    function collectProtocolFees(IERC20[] calldata tokens) external;

    /**
     * @notice Collects accumulated pool creator fees for the specified pool.
     * @dev Fees are sent to the pool creator address.
     * @param pool The address of the pool on which we are collecting pool creator fees
     */
    function collectPoolCreatorFees(address pool) external;

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
                         Yield-bearing tokens buffers
    *******************************************************************************/
    /**
     * @notice Enables vault buffers, used to wrap/unwrap yield-bearing tokens.
     * @dev The caller must be allowed by the current Authorizer to do this.
     */
    function enableVaultBuffers() external;

    /**
     * @notice Disables vault buffers.
     * @dev The caller must be allowed by the current Authorizer to do this.
     */
    function disableVaultBuffers() external;

    /**
     * @notice Adds liquidity to a buffer of yield-bearing tokens (linear pools embedded in the vault).
     *
     * @param wrappedToken Address of the wrapped token that implements IERC4626 interface
     * @param amountBaseRaw Amount of base tokens that will be deposited into the buffer
     * @param amountWrappedRaw Amount of wrapped tokens that will be deposited into the buffer
     * @param bufferSharesOwner Address of contract that will own the deposited liquidity. Only
     *        this contract will be able to remove liquidity from the buffer
     * @return issuedShares the amount of tokens sharesOwner has in the buffer, expressed in base token amounts
     *         (it is the BPT of vault's internal linear pools)
     */
    function addLiquidityBuffer(
        IERC4626 wrappedToken,
        uint256 amountBaseRaw,
        uint256 amountWrappedRaw,
        address bufferSharesOwner
    ) external returns (uint256 issuedShares);

    /**
     * @notice Removes liquidity from a buffer of yield-bearing token (linear pools embedded in the vault).
     * Only proportional exits are supported. This call is authenticated, so only members (routers) approved by the
     * DAO can remove the liquidity of a buffer, since the original caller cannot be identified.
     *
     * @param wrappedToken Address of the wrapped token that implements IERC4626 interface
     * @param sharesToRemove Amount of shares to remove from the buffer. Cannot be greater than sharesOwner
     *        total shares
     * @param sharesOwner Address of contract that owns the deposited liquidity.
     * @return removedBaseBalanceRaw Amount of base tokens returned to the user
     * @return removedWrappedBalanceRaw Amount of wrapped tokens returned to the user
     */
    function removeLiquidityBuffer(
        IERC4626 wrappedToken,
        uint256 sharesToRemove,
        address sharesOwner
    ) external returns (uint256 removedBaseBalanceRaw, uint256 removedWrappedBalanceRaw);

    /*******************************************************************************
                                Authentication
    *******************************************************************************/

    /**
     * @notice Sets a new Authorizer for the Vault.
     * @dev The caller must be allowed by the current Authorizer to do this.
     * Emits an `AuthorizerChanged` event.
     */
    function setAuthorizer(IAuthorizer newAuthorizer) external;
}
