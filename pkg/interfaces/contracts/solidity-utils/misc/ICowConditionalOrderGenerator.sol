// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";
import { ICowConditionalOrder, GPv2Order } from "./ICowConditionalOrder.sol";

/**
 * @title Conditional Order Generator Interface
 * @author mfw78 <mfw78@rndlabs.xyz>
 */
interface ICowConditionalOrderGenerator is IERC165 {
    /**
     * @dev This event is emitted when a new conditional order is created.
     * @param owner the address that has created the conditional order
     * @param params the address / salt / data of the conditional order
     */
    event ConditionalOrderCreated(address indexed owner, ICowConditionalOrder.ConditionalOrderParams params);

    /**
     * @dev Get a tradeable order that can be posted to the CoW Protocol API and would pass signature validation.
     *      **MUST** revert if the order condition is not met.
     * @param owner the contract who is the owner of the order
     * @param sender the `msg.sender` of the parent `isValidSignature` call
     * @param ctx the context of the order (bytes32(0) if Merkle tree is used, otherwise the H(params))
     * @param staticInput the static input for all discrete orders cut from this conditional order
     * @return the tradeable order for submission to the CoW Protocol API
     */
    function getTradeableOrder(
        address owner,
        address sender,
        bytes32 ctx,
        bytes calldata staticInput
    ) external view returns (GPv2Order memory);
}
