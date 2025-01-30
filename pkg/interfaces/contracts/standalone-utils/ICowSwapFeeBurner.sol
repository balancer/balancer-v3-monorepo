// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC1271 } from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { ICowConditionalOrderGenerator } from "./ICowConditionalOrderGenerator.sol";
import { ICowConditionalOrder, GPv2Order } from "./ICowConditionalOrder.sol";
import { IProtocolFeeBurner } from "./IProtocolFeeBurner.sol";

interface ICowSwapFeeBurner is IERC1271, IProtocolFeeBurner, ICowConditionalOrder, ICowConditionalOrderGenerator {
    enum OrderStatus {
        Nonexistent,
        Active,
        Filled,
        Failed
    }

    /**
     * @notice An order was retried after failing.
     * @param sellToken The token used to identify the order (tokenIn)
     * @param sellAmount The number of tokens in the order (tokenIn)
     * @param minTargetTokenAmount The minimum number of target tokens required (tokenOut)
     * @param deadline The deadline for the new order to be filled
     */
    event OrderRetried(IERC20 sellToken, uint256 sellAmount, uint256 minTargetTokenAmount, uint256 deadline);

    /**
     * @notice An order was canceled after failure.
     * @param sellToken The token used to identify the order (tokenIn)
     * @param sellAmount The number of tokens in the order (tokenIn)
     * @param receiver The account that received the tokens from the unfilled order
     */
    event OrderReverted(IERC20 sellToken, uint256 sellAmount, address receiver);

    /**
     * @notice The order parameters were invalid.
     * @param reason Text explaining the reason the order is invalid
     */
    error InvalidOrderParameters(string reason);

    /**
     * @notice Attempt to revert an order that had not failed.
     * @dev `revertOrder` should only be called when the OrderStatus is `Failed`.
     * @param actualStatus The status of the order when `revertOrder` was called
     */
    error OrderHasUnexpectedStatus(OrderStatus actualStatus);

    /// @notice Fails on SignatureVerifierMuxer due to compatibility issues with ComposableCow.
    error InterfaceIsSignatureVerifierMuxer();

    /**
     * @notice Get the order at the sell token.
     * @param sellToken The token used to identify the order (tokenIn)
     * @return The order data for the given token
     */
    function getOrder(IERC20 sellToken) external view returns (GPv2Order memory);

    /**
     * @notice Get the status of the order at the sell token.
     * @param sellToken The token used to identify the order (tokenIn)
     * @return The status of the order for the given token
     */
    function getOrderStatus(IERC20 sellToken) external view returns (OrderStatus);

    /**
     * @notice Retry an order that has not been filled yet and expired.
     * @param sellToken The token used to identify the order (tokenIn)
     * @param minTargetTokenAmount The minimum number of target tokens to receive (tokenOut)
     * @param deadline The deadline for the order to be filled.
     */
    function retryOrder(IERC20 sellToken, uint256 minTargetTokenAmount, uint256 deadline) external;

    /**
     * @notice Return tokens from an order that has failed.
     * @param sellToken The token used to identify the order (tokenIn)
     * @param receiver The address to receive the tokens from the unfilled order
     */
    function revertOrder(IERC20 sellToken, address receiver) external;

    /**
     * @notice Emergency return tokens from an order regardless of status.
     * @param sellToken The token used to identify the order (tokenIn)
     * @param receiver The address to receive the from the unfilled order
     */
    function emergencyRevertOrder(IERC20 sellToken, address receiver) external;
}
