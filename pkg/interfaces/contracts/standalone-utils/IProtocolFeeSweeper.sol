// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IProtocolFeeController } from "../vault/IProtocolFeeController.sol";
import { IProtocolFeeBurner } from "./IProtocolFeeBurner.sol";

interface IProtocolFeeSweeper {
    /**
     * @notice Emitted when the target token is set or updated.
     * @param token The preferred token for receiving protocol fees
     */
    event TargetTokenSet(IERC20 indexed token);

    /**
     * @notice Emitted when the fee recipient address is set or updated.
     * @param feeRecipient The final destination of collected protocol fees
     */
    event FeeRecipientSet(address indexed feeRecipient);

    /**
     * @notice Emitted when the protocol fee burner contract is set or updated.
     * @param protocolFeeBurner The contract used to "burn" protocol fees (i.e., convert them to the target token)
     */
    event ProtocolFeeBurnerSet(address indexed protocolFeeBurner);

    /**
     * @notice Emitted when a fee token is transferred directly, vs. calling the burner.
     * @dev This can happen if no target token or burner contract was specified, or the fee token is the target token.
     * @param pool The pool on which the fee was collected
     * @param feeToken The token the fee was collected in (also the target token in this case; no swap necessary)
     * @param feeTokenAmount The number of feeTokens
     * @param recipient The recipient of the fee tokens
     */
    event ProtocolFeeSwept(address indexed pool, IERC20 indexed feeToken, uint256 feeTokenAmount, address recipient);

    /// @notice The fee recipient is invalid.
    error InvalidFeeRecipient();

    /// @notice The target token is invalid.
    error InvalidTargetToken();

    /**
     * @notice Withdraw, convert, and forward protocol fees for a given pool and token.
     * @dev This will withdraw the fee token from the controller to this contract, and attempt to convert and forward
     * the proceeds to the fee recipient. Note that this requires governance to grant this contract permission to call
     * `withdrawProtocolFeesForToken` on the `ProtocolFeeController`.
     *
     * This is a permissioned call, since it involves a swap and a permissionless sweep could be triggered at times
     * disadvantageous to the protocol (e.g., flash crashes). The general design is for an off-chain process to
     * periodically collect fees from the Vault and check the protocol fee amounts available for withdrawal. Once
     * these are greater than a threshold, compute the expected proceeds to determine the limits (amount and deadline),
     * then call the sweeper to put in the order with the burner.
     *
     * @param pool The pool that incurred the fees we're withdrawing
     * @param feeToken The fee token in the pool
     * @param minAmountOut The minimum number of target tokens to be received
     * @param deadline Deadline for the burn operation (swap), after which it will revert
     */
    function sweepProtocolFeesForToken(address pool, IERC20 feeToken, uint256 minAmountOut, uint256 deadline) external;

    /**
     * @notice Return the address of the current `ProtocolFeeController` from the Vault.
     * @dev It is not immutable in the Vault, so we need to fetch it every time.
     * @return protocolFeeController The address of the current `ProtocolFeeController`
     */
    function getProtocolFeeController() external view returns (IProtocolFeeController);

    /**
     * @notice Getter for the target token.
     * @dev This is the token the burner will swap all fee tokens for. Can be changed by `setTargetToken`.
     * @return targetToken The current target token
     */
    function getTargetToken() external view returns (IERC20);

    /**
     * @notice Getter for the current fee recipient.
     * @dev Can be changed by `setFeeRecipient`.
     * @return feeRecipient The current fee recipient
     */
    function getFeeRecipient() external view returns (address);

    /**
     * @notice Getter for the current protocol fee burner.
     * @dev Can be changed by `setProtocolFeeBurner`.
     * @return protocolFeeBurner The currently active protocol fee burner
     */
    function getProtocolFeeBurner() external view returns (IProtocolFeeBurner);

    /**
     * @notice Update the fee recipient address.
     * @dev This is a permissioned function.
     * @param feeRecipient The address of the new fee recipient
     */
    function setFeeRecipient(address feeRecipient) external;

    /**
     * @notice Update the address of the protocol fee burner, used to convert protocol fees to a target token.
     * @dev This is a permissioned function. If it is not set, the contract will fall back to forwarding all fee tokens
     * directly to the fee recipient. Note that if this function is called, `setTargetToken` must be called as well,
     * or any sweep operations using the burner will revert with `InvalidTargetToken`.
     *
     * @param protocolFeeBurner The address of the current protocol fee burner
     */
    function setProtocolFeeBurner(IProtocolFeeBurner protocolFeeBurner) external;

    /**
     * @notice Update the address of the target token.
     * @dev This is the token for which the burner will attempt to swap all collected fee tokens.
     * @param targetToken The address of the target token
     */
    function setTargetToken(IERC20 targetToken) external;

    /**
     * @notice Retrieve any tokens "stuck" in this contract (e.g., dust, or failed conversions).
     * @dev It will recover the full balance of all the tokens. This can only be called by the `feeRecipient`.
     * @param feeTokens The tokens to recover
     */
    function recoverProtocolFees(IERC20[] memory feeTokens) external;
}
