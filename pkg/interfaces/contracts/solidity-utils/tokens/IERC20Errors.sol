// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

/**
 * @notice Custom errors for ERC20 tokens.
 * @dev See [EIP-6093](https://eips.ethereum.org/EIPS/eip-6093).
 */
interface IERC20Errors {
    /**
     * @dev Indicates an error related to the current balance of a sender. Used in transfers.
     * `balance` MUST be less than `needed`.
     */
    error ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed);

    /**
     * @dev Indicates a failure with the token sender. Used in transfers.
     */
    error ERC20InvalidSender(address sender);

    /**
     * @dev Indicates a failure with the token receiver. Used in transfers.
     */
    error ERC20InvalidReceiver(address receiver);

    /**
     * @dev Indicates a failure with the spender’s allowance. Used in transfers.
     */
    error ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed);

    /**
     * @dev Indicates a failure with the approver of a token to be approved. Used in approvals.
     */
    error ERC20InvalidApprover(address approver);

    /**
     * @dev Indicates a failure with the spender to be approved. Used in approvals.
     */
    error ERC20InvalidSpender(address spender);
}
