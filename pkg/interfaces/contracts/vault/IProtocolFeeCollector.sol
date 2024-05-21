// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "./IVault.sol";

enum ProtocolFeeType {
    SWAP,
    YIELD
}

interface IProtocolFeeCollector {
    /**
     * @notice Emitted when the aggregate protocol swap fee percentage is updated.
     * @dev This is a composite of the protocol swap fee and pool creator fee.
     * @param aggregateSwapFeePercentage The updated protocol swap fee percentage
     */
    event GlobalAggregateSwapFeePercentageChanged(uint256 aggregateSwapFeePercentage);

    /**
     * @notice Emitted when the aggregate protocol yield fee percentage is updated.
     * @dev This is a composite of the protocol yield fee and pool creator fee.
     * @param aggregateYieldFeePercentage The updated protocol yield fee percentage
     */
    event GlobalAggregateYieldFeePercentageChanged(uint256 aggregateYieldFeePercentage);

    /**
     * @notice Emitted when the aggregate protocol swap fee percentage is updated for a specific pool.
     * @param pool The pool whose protocol swap fee will be changed
     * @param aggregateSwapFeePercentage The updated aggregate protocol swap fee percentage
     */
    event AggregateSwapFeePercentageChanged(address indexed pool, uint256 aggregateSwapFeePercentage);

    /**
     * @notice Emitted when the aggregate protocol yield fee percentage is updated for a specific pool.
     * @param pool The pool whose protocol yield fee will be changed
     * @param aggregateYieldFeePercentage The updated aggregate protocol yield fee percentage
     */
    event AggregateYieldFeePercentageChanged(address indexed pool, uint256 aggregateYieldFeePercentage);

    /**
     * @notice Logs the collection of protocol swap and yield fees in a specific token and amount, for a given pool.
     * @dev Note that since charging protocol fees occurs in the Vault, but fee collection happens in the
     * ProtocolFeeCollector, the fees reported here are for swap and yield together, and may encompass multiple
     * operations.
     *
     * @param pool The pool on which the fee was charged
     * @param token The token in which the fee was charged
     * @param amount The total amount of the token collected in fees
     */
    event ProtocolFeeCollected(address indexed pool, IERC20 indexed token, uint256 amount);

    /**
     * @dev Error raised when the aggregate protocol swap fee percentage exceeds the maximum allowed value.
     * Note that this is checked for both the global and pool-specific protocol swap fee percentages.
     */
    error AggregateSwapFeePercentageTooHigh();

    /**
     * @dev Error raised when the aggregate protocol yield fee percentage exceeds the maximum allowed value.
     * Note that this is checked for both the global and pool-specific protocol swap fee percentages.
     */
    error AggregateYieldFeePercentageTooHigh();

    /// @dev Error raised if there is no pool creator on a withdrawal attempt from the given pool.
    error PoolCreatorNotRegistered(address pool);

    /// @dev Error raised if the wrong account attempts to withdraw pool creator fees.
    error CallerIsNotPoolCreator(address caller);

    /// @dev The fee percentages are inconsistent (e.g., there is a creator fee, with no creator).
    error InvalidFeeConfiguration();

    /// @dev Returns the main Vault address.
    function vault() external view returns (IVault);

    /**
     * @notice Getter for the current global aggregate protocol swap fee.
     * @return aggregateSwapFeePercentage The global protocol swap fee percentage
     */
    function getGlobalAggregateSwapFeePercentage() external view returns (uint256);

    /**
     * @notice Getter for the current global aggregate protocol yield fee.
     * @return aggregateYieldFeePercentage The global protocol yield fee percentage
     */
    function getGlobalAggregateYieldFeePercentage() external view returns (uint256);

    /**
     * @notice Called by the Vault when protocol swap and yield fees are collected.
     * @dev This must be called from the Vault, during permissionless collection. Note that since charging protocol
     * fees occurs in the Vault, but fee collection happens in the ProtocolFeeCollector, the fees reported here are
     * for both swap and yield, and may encompass multiple operations.
     *
     * @param pool The pool on which the swap fee was charged
     * @param token The token in which the swap fee was charged
     * @param amount The amount of the token collected in fees
     */
    function receiveProtocolFees(address pool, IERC20 token, uint256 amount) external;

    /**
     * @notice Returns the collected protocol fee amount of each pool token.
     * @dev Includes both swap and yield protocol fees. Since this forces fee collection, this all might be very
     * expensive if there are uncollected or aggregated fees.
     *
     * @param pool The pool on which fees were collected
     * @param feeAmounts The amount that can be withdrawn; array corresponds to the token array
     */
    function getCollectedProtocolFeeAmounts(address pool) external returns (uint256[] memory feeAmounts);

    /**
     * @notice Returns the collected pool creator fee amount of each pool token.
     * @dev Includes both swap and yield pool creator fees. Since this forces fee collection, this all might be very
     * expensive if there are uncollected or aggregated fees.
     *
     * @param pool The pool on which fees were collected
     * @param feeAmounts The amount that can be withdrawn; array corresponds to the token array
     */
    function getCollectedPoolCreatorFeeAmounts(address pool) external returns (uint256[] memory feeAmounts);

    // Permissioned functions

    /**
     * @notice Set the global aggregate protocol swap fee percentage, used by standard pools.
     * @param newAggregateSwapFeePercentage The new protocol swap fee percentage
     */
    function setGlobalAggregateSwapFeePercentage(uint256 newAggregateSwapFeePercentage) external;

    /**
     * @notice Set the global aggregate protocol yield fee percentage, used by standard pools.
     * @param newAggregateYieldFeePercentage The new protocol yield fee percentage
     */
    function setGlobalAggregateYieldFeePercentage(uint256 newAggregateYieldFeePercentage) external;

    /**
     * @notice Override the aggregate protocol swap fee percentage for a specific pool.
     * @param pool The pool we are setting the aggregate protocol swap fee on
     * @param newAggregateSwapFeePercentage The new aggregate protocol swap fee percentage for the specific pool
     */
    function setAggregateSwapFeePercentage(address pool, uint256 newAggregateSwapFeePercentage) external;

    /**
     * @notice Override the aggregate protocol yield fee percentage for a specific pool.
     * @param pool The pool we are setting the aggregate protocol yield fee on
     * @param newAggregateYieldFeePercentage The new protocol yield fee percentage
     */
    function setAggregateYieldFeePercentage(address pool, uint256 newAggregateYieldFeePercentage) external;

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
