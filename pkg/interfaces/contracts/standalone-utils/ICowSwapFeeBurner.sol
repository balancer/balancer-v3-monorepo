// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC1271 } from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";

import { IProtocolFeeBurner } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IProtocolFeeBurner.sol";
import {
    ICowConditionalOrder,
    GPv2Order
} from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/ICowConditionalOrder.sol";

interface ICowSwapFeeBurner is IERC165, IERC1271, IProtocolFeeBurner, ICowConditionalOrder {
    error OrderIsNotExist();
    error NonZeroOffchainInput();
    error InvalidOrder();
    error TargetTokenIsFeeToken();
    error FeeTokenAmountIsZero();
    error PriceIsZero();

    function getOrder(uint256 orderIndex) external view returns (GPv2Order memory);
}
