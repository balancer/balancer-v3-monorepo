// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IProtocolFeeCollector {
    /**
     * @notice Emitted when the protocol swap fee percentage is updated.
     * @param swapFeePercentage The updated protocol swap fee percentage
     */
    event ProtocolSwapFeePercentageChanged(uint256 swapFeePercentage);

    /**
     * @notice Emitted when the protocol yield fee percentage is updated.
     * @param yieldFeePercentage The updated protocol yield fee percentage
     */
    event ProtocolYieldFeePercentageChanged(uint256 yieldFeePercentage);

    /**
     * @notice Logs the collection of fees in a specific token and amount.
     * @param token The token in which the fee has been collected
     * @param amount The amount of the token collected as fees
     * @param recipient The address where funds were sent
     */
    event ProtocolFeeWithdrawn(IERC20 indexed token, uint256 indexed amount, address indexed recipient);

    /// @dev Error raised when the protocol swap fee percentage exceeds the maximum allowed value.
    error ProtocolSwapFeePercentageTooHigh();

    /// @dev Error raised when the protocol yield fee percentage exceeds the maximum allowed value.
    error ProtocolYieldFeePercentageTooHigh();

    /**
     * @notice Gets the current swap fee percentage for the protocol.
     * @return swapFeePercentage The new swap fee percentage to be set
     */
    function getProtocolSwapFeePercentage() external view returns (uint256);

    /**
     * @notice Gets the current yield fee percentage for the protocol.
     * @return yieldFeePercentage The new swap fee percentage to be set
     */
    function getProtocolYieldFeePercentage() external view returns (uint256);

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
     * @notice Returns the collected fee amount of each token on the list (i.e., held by this contract).
     * @param tokens The list of tokens fees have been collected on
     * @param feeAmounts The amount that can be withdrawn ()
     */
    function getCollectedFeeAmounts(IERC20[] memory tokens) external view returns (uint256[] memory feeAmounts);

    /**
     * @notice Withdraw collected protocol fees for a set of tokens, to the given recipient address.
     * @param tokens List of tokens to withdraw
     * @param recipient Recipient address for the withdrawn protocol fees
     */
    function withdrawCollectedFees(IERC20[] calldata tokens, address recipient) external;
}
