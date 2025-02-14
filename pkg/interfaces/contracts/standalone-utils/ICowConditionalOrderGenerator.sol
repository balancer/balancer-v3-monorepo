// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";

import { ICowConditionalOrder, GPv2Order } from "./ICowConditionalOrder.sol";

/**
 * @notice Conditional Order Generator Interface
 * @author mfw78 <mfw78@rndlabs.xyz>
 */
interface ICowConditionalOrderGenerator is IERC165 {
    /**
     * @dev Emitted when a new conditional order is created.
     * @param owner The address that created the conditional order
     * @param params The conditional order data
     */
    event ConditionalOrderCreated(address indexed owner, ICowConditionalOrder.ConditionalOrderParams params);

    /**
     * @notice Get a tradeable order that can be posted to the CoW Protocol API and would pass signature validation.
     * @dev **MUST** revert if the order conditions are not met.
     * @param owner The owner of the order (usually a contract)
     * @param sender The `msg.sender` of the parent `isValidSignature` call
     * @param ctx The context of the order (bytes32(0) if Merkle tree is used, otherwise the H(params))
     * @param staticInput Conditional order type-specific data known at time of creation for all discrete orders
     * @param offchainInput Off-chain input (similar to Balancer `userData`); currently unused
     * @return order Tradeable order for submission to the CoW Protocol API
     */
    function getTradeableOrder(
        address owner,
        address sender,
        bytes32 ctx,
        bytes calldata staticInput,
        bytes calldata offchainInput
    ) external view returns (GPv2Order memory);
}
