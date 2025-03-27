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
     * @notice Emitted when a fee token is transferred directly, vs. calling the burner.
     * @dev This can happen if no target token or burner contract was specified, or the fee token is the target token.
     * @param pool The pool on which the fee was collected
     * @param feeToken The token the fee was collected in (also the target token in this case; no swap necessary)
     * @param feeTokenAmount The number of feeTokens
     * @param recipient The recipient of the fee tokens
     */
    event ProtocolFeeSwept(address indexed pool, IERC20 indexed feeToken, uint256 feeTokenAmount, address recipient);

    /**
     * @notice Emitted when a burner is added to the protocol fee burner allowlist.
     * @dev `sweepProtocolFeesForToken` can only be called with approved protocol fee burner addresses.
     * @param protocolFeeBurner The address of the approved protocol fee burner that was added
     */
    event ProtocolFeeBurnerAdded(address indexed protocolFeeBurner);

    /**
     * @notice Emitted when a burner is removed from the protocol fee burner allowlist.
     * @dev `sweepProtocolFeesForToken` can only be called with approved protocol fee burner addresses.
     * @param protocolFeeBurner The address of the approved protocol fee burner that was removed
     */
    event ProtocolFeeBurnerRemoved(address indexed protocolFeeBurner);

    /// @notice The fee recipient is invalid.
    error InvalidFeeRecipient();

    /// @notice The target token is invalid.
    error InvalidTargetToken();

    /// @notice The protocol fee burner to be added is invalid.
    error InvalidProtocolFeeBurner();

    /**
     * @notice The specified fee burner has not been approved.
     * @param protocolFeeBurner The address of the unsupported fee burner
     */
    error UnsupportedProtocolFeeBurner(address protocolFeeBurner);

    /**
     * @notice Protocol fee burners can only be added to the allowlist once.
     * @param protocolFeeBurner The address of an approved protocol fee burner
     */
    error ProtocolFeeBurnerAlreadyAdded(address protocolFeeBurner);

    /**
     * @notice Protocol fee burners must be added to the allowlist before being removed.
     * @param protocolFeeBurner The address of a protocol fee burner to be removed from the allowlist
     */
    error ProtocolFeeBurnerNotAdded(address protocolFeeBurner);

    /**
     * @notice The burner did not consume its entire allowance.
     * @dev The fee sweeper approves the burner to pull tokens. If it doesn't do so, revert to avoid a "hanging"
     * approval that could be exploited later.
     */
    error BurnerDidNotConsumeAllowance();

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
     * @param minTargetTokenAmountOut The minimum number of target tokens to be received
     * @param deadline Deadline for the burn operation (swap), after which it will revert
     * @param feeBurner The protocol fee burner to be used (or the zero address to fall back on direct transfer)
     */
    function sweepProtocolFeesForToken(
        address pool,
        IERC20 feeToken,
        uint256 minTargetTokenAmountOut,
        uint256 deadline,
        IProtocolFeeBurner feeBurner
    ) external;

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
     * @notice Check whether a given address corresponds to an approved protocol fee burner.
     * @param protocolFeeBurner The address to be checked
     * @return isApproved True if the given address is on the approved protocol fee burner allowlist
     */
    function isApprovedProtocolFeeBurner(address protocolFeeBurner) external view returns (bool);

    /**
     * @notice Update the fee recipient address.
     * @dev This is a permissioned function.
     * @param feeRecipient The address of the new fee recipient
     */
    function setFeeRecipient(address feeRecipient) external;

    /**
     * @notice Update the address of the target token.
     * @dev This is the token for which the burner will attempt to swap all collected fee tokens.
     * @param targetToken The address of the target token
     */
    function setTargetToken(IERC20 targetToken) external;

    /**
     * @notice Add an approved fee burner to the allowlist.
     * @dev This is a permissioned call. `sweepProtocolFeesForToken` can only be called with approved protocol
     * fee burners.
     *
     * @param protocolFeeBurner The address of an approved protocol fee burner to be added
     */
    function addProtocolFeeBurner(IProtocolFeeBurner protocolFeeBurner) external;

    /**
     * @notice Remove a fee burner from the allowlist.
     * @dev This is a permissioned call. `sweepProtocolFeesForToken` can only be called with approved protocol
     * fee burners.
     *
     * @param protocolFeeBurner The address of a protocol fee burner on the allowlist to be removed
     */
    function removeProtocolFeeBurner(IProtocolFeeBurner protocolFeeBurner) external;

    /**
     * @notice Retrieve any tokens "stuck" in this contract (e.g., dust, or failed conversions).
     * @dev It will recover the full balance of all the tokens. This can only be called by the `feeRecipient`.
     * @param feeTokens The tokens to recover
     */
    function recoverProtocolFees(IERC20[] memory feeTokens) external;
}
