// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { PoolFeeConfig } from "./VaultTypes.sol";
import { IVault } from "./IVault.sol";

enum ProtocolFeeType {
    SWAP,
    YIELD
}

interface IProtocolFeeCollector {
    /**
     * @notice Emitted when the protocol swap fee percentage is updated.
     * @param swapFeePercentage The updated protocol swap fee percentage
     */
    event GlobalProtocolSwapFeePercentageChanged(uint256 swapFeePercentage);

    /**
     * @notice Emitted when the protocol yield fee percentage is updated.
     * @param yieldFeePercentage The updated protocol yield fee percentage
     */
    event GlobalProtocolYieldFeePercentageChanged(uint256 yieldFeePercentage);

    /**
     * @notice Emitted when the protocol swap fee percentage is updated for a specific pool.
     * @param pool The pool whose protocol swap fee will be changed
     * @param swapFeePercentage The updated protocol swap fee percentage
     */
    event ProtocolSwapFeePercentageChanged(address indexed pool, uint256 swapFeePercentage);

    /**
     * @notice Emitted when the protocol yield fee percentage is updated for a specific pool.
     * @param pool The pool whose protocol yield fee will be changed
     * @param yieldFeePercentage The updated protocol yield fee percentage
     */
    event ProtocolYieldFeePercentageChanged(address indexed pool, uint256 yieldFeePercentage);

    /**
     * @notice Emitted when the pool creator fee percentage is updated.
     * @param poolCreatorFeePercentage The updated pool creator fee percentage
     */
    event PoolCreatorFeePercentageChanged(address indexed pool, uint256 poolCreatorFeePercentage);

    /**
     * @notice Logs the collection of protocol swap fees in a specific token and amount.
     * @param pool The pool on which the swap fee was charged
     * @param token The token in which the swap fee was charged
     * @param amount The amount of the token collected in fees
     */
    event ProtocolSwapFeeCollected(address indexed pool, IERC20 indexed token, uint256 amount);

    /**
     * @notice Logs the collection of protocol yield fees in a specific token and amount.
     * @param pool The pool on which the yield fee was charged
     * @param token The token in which the yield fee was charged
     * @param amount The amount of the token collected in fees
     */
    event ProtocolYieldFeeCollected(address indexed pool, IERC20 indexed token, uint256 amount);

    /// @dev Error raised when the protocol swap fee percentage exceeds the maximum allowed value.
    error ProtocolSwapFeePercentageTooHigh();

    /// @dev Error raised when the protocol yield fee percentage exceeds the maximum allowed value.
    error ProtocolYieldFeePercentageTooHigh();

    /// @dev Error raised when the pool creator fee percentage exceeds the maximum allowed value.
    error PoolCreatorFeePercentageTooHigh();

    /// @dev Error raised if there is no pool creator on a withdrawal attempt from the given pool.
    error PoolCreatorNotRegistered(address pool);

    /// @dev Error raised if the wrong account attempts to withdraw pool creator fees.
    error CallerIsNotPoolCreator(address caller);

    /// @dev The fee percentages are inconsistent (e.g., there is a creator fee, with no creator).
    error InvalidFeeConfiguration();

    /// @dev Returns the main Vault address.
    function vault() external view returns (IVault);

    /**
     * @notice Getter for the current suggested global protocol swap fee.
     * @return protocolSwapFeePercentage The global protocol swap fee percentage
     */
    function getGlobalProtocolSwapFeePercentage() external view returns (uint256);

    /**
     * @notice Getter for the current suggested global protocol yield fee.
     * @return protocolYieldFeePercentage The global protocol yield fee percentage
     */
    function getGlobalProtocolYieldFeePercentage() external view returns (uint256);

    /**
     * @notice Get the current creator fee percentage for a pool.
     * @param pool The pool on which pool creator fees are collected
     * @return poolCreator Address of the registered pool creator
     */
    function getPoolCreator(address pool) external view returns (address);

    /**
     * @notice Compute and return the aggregate percentage, and store it locally for later disaggregation.
     * @dev It will use the global protocol yield fee percentage. Projects can use the TokenConfig to exempt
     * particular tokens from yield fees, so it does not need to be customized here.
     * @param pool The pool being registered
     * @param feeConfig The pool-specific fees (and pool creator)
     */
    function registerPoolFeeConfig(address pool, PoolFeeConfig calldata feeConfig) external returns (uint256, uint256);

    /**
     * @notice Called by the Vault when protocol swap fees are collected.
     * @dev This must be called from the Vault, during permissionless collection.
     * @param pool The pool on which the swap fee was charged
     * @param token The token in which the swap fee was charged
     * @param amount The amount of the token collected in fees
     */
    function receiveProtocolSwapFees(address pool, IERC20 token, uint256 amount) external;

    /**
     * @notice Called by the Vault when protocol swap fees are collected.
     * @dev This must be called from the Vault, during permissionless collection.
     * @param pool The pool on which the yield fee was charged
     * @param token The token in which the yield fee was charged
     * @param amount The amount of the token collected in fees
     */
    function receiveProtocolYieldFees(address pool, IERC20 token, uint256 amount) external;

    /**
     * @notice Returns the collected protocol fee amount of each token on the list (i.e., held by this contract).
     * @dev Includes both swap and yield fees.
     * @param pool The pool on which fees were collected
     * @param feeAmounts The amount that can be withdrawn; array corresponds to the token array
     */
    function getCollectedProtocolFeeAmounts(address pool) external returns (uint256[] memory feeAmounts);

    /**
     * @notice Returns the collected pool creator fee amount of each token on the list (i.e., held by this contract).
     * @dev Includes both swap and yield fees.
     * @param pool The pool on which fees were collected
     * @param feeAmounts The amount that can be withdrawn; array corresponds to the token array
     */
    function getCollectedPoolCreatorFeeAmounts(address pool) external returns (uint256[] memory feeAmounts);

    // Permissioned functions

    /**
     * @notice Set the suggested global protocol swap fee percentage.
     * @param newProtocolSwapFeePercentage The new protocol swap fee percentage
     */
    function setGlobalProtocolSwapFeePercentage(uint256 newProtocolSwapFeePercentage) external;

    /**
     * @notice Set the suggested global protocol yield fee percentage.
     * @param newProtocolYieldFeePercentage The new protocol yield fee percentage
     */
    function setGlobalProtocolYieldFeePercentage(uint256 newProtocolYieldFeePercentage) external;

    /**
     * @notice Override the protocol swap fee percentage for a specific pool.
     * @param pool The pool we are setting the protocol swap fee on
     * @param newProtocolSwapFeePercentage The new protocol swap fee percentage for the specific pool
     */
    function setProtocolSwapFeePercentage(address pool, uint256 newProtocolSwapFeePercentage) external;

    /**
     * @notice Override the protocol yield fee percentage for a specific pool.
     * @param pool The pool we are setting the protocol yield fee on
     * @param newProtocolYieldFeePercentage The new protocol yield fee percentage
     */
    function setProtocolYieldFeePercentage(address pool, uint256 newProtocolYieldFeePercentage) external;

    /**
     * @notice Set the creator fee for a pool.
     * @param pool The pool to set the pool creator fee on
     * @param newPoolCreatorFeePercentage The new pool creator fee percentage
     */
    function setPoolCreatorFeePercentage(address pool, uint256 newPoolCreatorFeePercentage) external;

    /**
     * @notice Withdraw collected protocol fees for a set of tokens.
     * @dev Sends swap and yield protocol fees to the recipient.
     * @param pool The pool on which fees were collected
     * @param recipient Address to send the tokens
     */
    function withdrawProtocolFees(address pool, address recipient) external;

    /**
     * @notice Withdraw collected pool creator fees for a set of tokens.
     * @dev Sends swap and yield pool creator fees to the recipient.
     * @param pool The pool on which fees were collected
     * @param recipient Address to send the tokens
     */
    function withdrawPoolCreatorFees(address pool, address recipient) external;
}
