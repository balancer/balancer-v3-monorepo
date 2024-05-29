// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "./IVault.sol";

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
     * @notice Logs the collection of protocol swap fees in a specific token and amount.
     * @dev Note that since charging protocol fees (i.e., distributing tokens between pool and fee balances) occurs
     * in the Vault, but fee collection happens in the ProtocolFeeCollector, the swap fees reported here may encompass
     * multiple operations.
     *
     * @param pool The pool on which the swap fee was charged
     * @param token The token in which the swap fee was charged
     * @param amount The amount of the token collected in fees
     */
    event ProtocolSwapFeeCollected(address indexed pool, IERC20 indexed token, uint256 amount);

    /**
     * @notice Logs the collection of protocol yield fees in a specific token and amount.
     * @dev Note that since charging protocol fees (i.e., distributing tokens between pool and fee balances) occurs
     * in the Vault, but fee collection happens in the ProtocolFeeCollector, the yield fees reported here may encompass
     * multiple operations.
     *
     * @param pool The pool on which the yield fee was charged
     * @param token The token in which the yield fee was charged
     * @param amount The amount of the token collected in fees
     */
    event ProtocolYieldFeeCollected(address indexed pool, IERC20 indexed token, uint256 amount);

    /**
     * @dev Error raised when the protocol swap fee percentage exceeds the maximum allowed value. Note that this is
     * checked for both the global and pool-specific protocol swap fee percentages.
     */
    error ProtocolSwapFeePercentageTooHigh();

    /**
     * @dev Error raised when the protocol yield fee percentage exceeds the maximum allowed value. Note that this is
     * checked for both the global and pool-specific protocol swap fee percentages.
     */
    error ProtocolYieldFeePercentageTooHigh();

    /// @dev Error raised if there is no pool creator on a withdrawal attempt from the given pool.
    error PoolCreatorNotRegistered(address pool);

    /// @dev Error raised if the wrong account attempts to withdraw pool creator fees.
    error CallerIsNotPoolCreator(address caller);

    /// @dev Returns the main Vault address.
    function vault() external view returns (IVault);

    /**
     * @notice Getter for the current global protocol swap fee.
     * @return protocolSwapFeePercentage The global protocol swap fee percentage
     */
    function getGlobalProtocolSwapFeePercentage() external view returns (uint256);

    /**
     * @notice Getter for the current global protocol yield fee.
     * @return protocolYieldFeePercentage The global protocol yield fee percentage
     */
    function getGlobalProtocolYieldFeePercentage() external view returns (uint256);

    /**
     * @notice Getter for the current protocol swap fee for a given pool.
     * @param pool The pool
     * @return protocolSwapFeePercentage The global protocol swap fee percentage
     * @return isOverride True if the protocol fee has been overridden
     */
    function getPoolProtocolSwapFeeInfo(address pool) external view returns (uint256, bool);

    /**
     * @notice Getter for the current protocol yield fee for a given pool.
     * @param pool The pool
     * @return protocolYieldFeePercentage The global protocol yield fee percentage
     * @return isOverride True if the protocol fee has been overridden
     */
    function getPoolProtocolYieldFeeInfo(address pool) external view returns (uint256, bool);

    /**
     * @notice Compute and return the aggregate percentage.
     * @dev This can be called after initialization (e.g., when the pool creator fee is updated), and uses the existing
     * protocol fee percentages for the pool.
     *
     * @param pool The pool being registered
     * @param poolCreatorFeePercentage The creator fee percentage for the pool
     * @return aggregateProtocolSwapFeePercentage The aggregate swap fee percentage (protocol and creator fees)
     * @return aggregateProtocolYieldFeePercentage The aggregate swap fee percentage (protocol and creator fees)
     */
    function computeAggregatePercentages(
        address pool,
        uint256 poolCreatorFeePercentage
    ) external view returns (uint256 aggregateProtocolSwapFeePercentage, uint256 aggregateProtocolYieldFeePercentage);

    /**
     * @notice Returns the amount of each pool token allocated to the protocol for withdrawal.
     * @dev Includes both swap and yield fees.
     * @param pool The pool on which fees were collected
     * @param feeAmounts The total amounts of each token that are available for withdrawal, in token registration order
     */
    function getAggregateProtocolFeeAmounts(address pool) external view returns (uint256[] memory feeAmounts);

    /**
     * @notice Returns the amount of each pool token allocated to the pool creator for withdrawal.
     * @dev Includes both swap and yield fees.
     * @param pool The pool on which fees were collected
     * @param feeAmounts The total amounts of each token that are available for withdrawal, in token registration order
     */
    function getAggregatePoolCreatorFeeAmounts(address pool) external view returns (uint256[] memory feeAmounts);

    /**
     * @notice Override the protocol swap fee percentage for a specific pool.
     * @dev This is a permissionless call, and will set the pool's fee to the current global fee, if it is different
     * from the current value, and the fee is not controlled by governance (i.e., has never been overridden).
     *
     * @param pool The pool we are setting the protocol swap fee on
     */
    function updateProtocolSwapFeePercentage(address pool) external;

    /**
     * @notice Override the protocol yield fee percentage for a specific pool.
     * @dev This is a permissionless call, and will set the pool's fee to the current global fee, if it is different
     * from the current value, and the fee is not controlled by governance (i.e., has never been overridden).
     *
     * @param pool The pool we are setting the protocol yield fee on
     */
    function updateProtocolYieldFeePercentage(address pool) external;

    /***************************************************************************
                                Permissioned Functions
    ***************************************************************************/

    /**
     * @notice Add pool-specific entries to the protocol swap and yield percentages.
     * @dev This must be called from the Vault during pool registration. It will initialize the pool to the global
     * protocol fee percentage values, and return the initial aggregate protocol fee percentages, based on an
     * initial pool creator fee of 0.
     *
     * @param pool The pool being registered
     * @return aggregateProtocolSwapFeePercentage The initial aggregate protocol swap fee percentage
     * @return aggregateProtocolYieldFeePercentage The initial aggregate protocol yield fee percentage
     */
    function registerPool(
        address pool
    ) external returns (uint256 aggregateProtocolSwapFeePercentage, uint256 aggregateProtocolYieldFeePercentage);

    /**
     * @notice Called by the Vault when protocol swap or yield fees are collected.
     * @dev This must be called from the Vault, during permissionless collection. Note that since charging protocol
     * fees (i.e., distributing tokens between pool and fee balances) occurs in the Vault, but fee collection
     * happens in the ProtocolFeeCollector, the swap fees reported here may encompass multiple operations.
     *
     * @param pool The pool on which the swap fees were charged
     * @param swapFeeAmounts An array parallel to the pool tokens, with the swap fees collected in each token
     * @param yieldFeeAmounts An array parallel to the pool tokens, with the yield fees collected in each token
     */
    function receiveProtocolFees(
        address pool,
        uint256[] memory swapFeeAmounts,
        uint256[] memory yieldFeeAmounts
    ) external;

    /**
     * @notice Set the global protocol swap fee percentage, used by standard pools.
     * @param newProtocolSwapFeePercentage The new protocol swap fee percentage
     */
    function setGlobalProtocolSwapFeePercentage(uint256 newProtocolSwapFeePercentage) external;

    /**
     * @notice Set the global protocol yield fee percentage, used by standard pools.
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
     * @notice Withdraw collected protocol fees for a given pool.
     * @dev Sends swap and yield protocol fees to the recipient.
     * @param pool The pool on which fees were collected
     * @param recipient Address to send the tokens
     */
    function withdrawProtocolFees(address pool, address recipient) external;

    /**
     * @notice Withdraw collected pool creator fees for a given pool.
     * @dev Sends swap and yield pool creator fees to the recipient.
     * @param pool The pool on which fees were collected
     * @param recipient Address to send the tokens
     */
    function withdrawPoolCreatorFees(address pool, address recipient) external;
}
