// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC1271 } from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";

import { ICowConditionalOrder, GPv2Order } from "../solidity-utils/misc/ICowConditionalOrder.sol";
import { IProtocolFeeBurner } from "./IProtocolFeeBurner.sol";

interface ICowSwapFeeBurner is IERC165, IERC1271, IProtocolFeeBurner, ICowConditionalOrder {
    error OrderIsNotExist();
    error NonZeroOffchainInput();
    error InvalidOrder();
    error TargetTokenIsFeeToken();
    error FeeTokenAmountIsZero();
    error MinTargetTokenAmountIsZero();

    /**
     * @notice Get the order at the given index.
     * @param orderIndex The index of the order.
     * @return The order at the given index.
     */
    function getOrder(uint256 orderIndex) external view returns (GPv2Order memory);
}
