// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC1271 } from "@openzeppelin/contracts/interfaces/IERC1271.sol";

import { ICowConditionalOrder, GPv2Order } from "../solidity-utils/misc/ICowConditionalOrder.sol";
import { ICowConditionalOrderGenerator } from "../solidity-utils/misc/ICowConditionalOrderGenerator.sol";
import { IProtocolFeeBurner } from "./IProtocolFeeBurner.sol";

interface ICowSwapFeeBurner is IERC1271, IProtocolFeeBurner, ICowConditionalOrder, ICowConditionalOrderGenerator {
    enum OrderStatus {
        NotExist,
        Active,
        Filled,
        Failed
    }

    error InvalidOrderParameters(string reason);
    error NonZeroOffchainInput();
    error OrderHasUnexpectedStatus(OrderStatus actualStatus);
    error InterfaceIsSignatureVerifierMuxer();

    event OrderRetried(IERC20 sellToken, uint256 sellAmount, uint256 minTargetTokenAmount, uint256 deadline);
    event OrderReverted(IERC20 sellToken, address receiver, uint256 sellAmount);

    /**
     * @notice Get the order at the sell token.
     * @param sellToken The token to sell in the order.
     * @return The order at the sell token.
     */
    function getOrder(IERC20 sellToken) external view returns (GPv2Order memory);

    /**
     * @notice Get the status of the order at the sell token.
     * @param sellToken The token to sell in the order.
     * @return The status of the order at the sell token.
     */
    function getOrderStatus(IERC20 sellToken) external view returns (OrderStatus);

    /**
     * @notice Retry an order that has not been filled yet and expired.
     * @param sellToken The token to sell in the order.
     * @param minTargetTokenAmount The minimum amount of target tokens to receive.
     * @param deadline The deadline for the order to be filled.
     */
    function retryOrder(IERC20 sellToken, uint256 minTargetTokenAmount, uint256 deadline) external;

    /**
     * @notice Return tokens from an order that has not been filled yet and expired.
     * @param sellToken The token to sell in the order.
     * @param receiver The address to receive the tokens.
     */
    function revertOrder(IERC20 sellToken, address receiver) external;

    /**
     * @notice Emergency revert tokens from an order that has not been filled yet and expired.
     * @param sellToken The token to sell in the order.
     * @param receiver The address to receive the tokens.
     */
    function emergencyRevertOrder(IERC20 sellToken, address receiver) external;
}
