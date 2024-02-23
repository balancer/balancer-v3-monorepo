// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IAuthorizer } from "./IAuthorizer.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IVaultAdmin {
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
     * @notice Emitted when the swap fee percentage of a pool is updated.
     * @param swapFeePercentage The new swap fee percentage for the pool
     */
    event SwapFeePercentageChanged(address indexed pool, uint256 indexed swapFeePercentage);

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
