// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

/**
 * @notice Custom errors for ERC20 tokens.
 * @dev See [EIP-6093](https://eips.ethereum.org/EIPS/eip-6093).
 */
interface IERC20Errors {
    /// @dev The sender of a transfer has insufficient funds.
    error ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed);

    /// @dev The sender of a transfer is invalid (e.g., the zero address).
    error ERC20InvalidSender(address sender);

    /// @dev The receiver of a transfer is invalid (e.g., the zero address).
    error ERC20InvalidReceiver(address receiver);

    /// @dev A spender has not been granted sufficient allowance to perform a transfer.
    error ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed);

    /// @dev The approver (owner) associated with an approval operation is invalid (e.g., the zero address).
    error ERC20InvalidApprover(address approver);

    /// @dev The spender associated with an approval operation is invalid (e.g., the zero address).
    error ERC20InvalidSpender(address spender);
}
