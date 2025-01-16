// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IProtocolFeeSweeper {
    /**
     * @notice Emitted when the target token is updated.
     * @param token The preferred token for receiving protocol fees
     */
    event TargetTokenSet(IERC20 indexed token);

    /**
     * @notice Emitted when the fee recipient address is verified.
     * @param feeRecipient The final destination of collected protocol fees
     */
    event FeeRecipientSet(address indexed feeRecipient);

    /**
     * @notice Emitted when governance has set the protocol fee burner contract.
     * @param protocolFeeBurner The contract used to "burn" protocol fees (i.e., convert them to the target token)
     */
    event ProtocolFeeBurnerSet(address indexed protocolFeeBurner);

    /**
     * @notice Emitted when a fee token has been burned.
     * @dev This means it was converted to the target and sent to the recipient.
     * @param pool The pool the fee was collected on
     * @param feeToken The token the fee was collected in
     * @param feeTokenAmount The number of feeTokens to be swapped for the target token
     * @param targetToken The target token to exchange the fee token for
     * @param targetTokenAmount The number of target tokens the burner swapped for the fee tokens
     * @param protocolFeeBurner The address of the burner contract that performed the swap
     * @param recipient The recipient of the target tokens
     */
    event ProtocolFeeBurned(
        address indexed pool,
        IERC20 indexed feeToken,
        uint256 feeTokenAmount,
        IERC20 indexed targetToken,
        uint256 targetTokenAmount,
        address protocolFeeBurner,
        address recipient
    );

    /**
     * @notice Emitted when a fee token is transferred directly.
     * @dev This happens when the fee token is already the target token.
     * @param pool The pool the fee was collected on
     * @param feeToken The token the fee was collected in (also the target token in this case; no swap necessary)
     * @param feeTokenAmount The number of feeTokens
     * @param recipient The recipient of the target tokens
     */
    event ProtocolFeeTransferred(
        address indexed pool,
        IERC20 indexed feeToken,
        uint256 feeTokenAmount,
        address recipient
    );

    /**
     * @notice Withdraw, convert, and forward protocol fees for a given pool.
     * @dev This will withdraw all fee tokens to this contract, and attempt to convert and forward them. There is also
     * a single token pool withdrawal, but that is an edge case not in scope for the sweeper.
     *
     * @param pool The pool from which we're withdrawing fees
     */
    function sweepProtocolFees(address pool) external;
}
