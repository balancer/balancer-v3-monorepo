// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { ICowConditionalOrder } from "./ICowConditionalOrder.sol";

interface IComposableCow {
    struct PayloadStruct {
        bytes32[] proof;
        ICowConditionalOrder.ConditionalOrderParams params;
        bytes offchainInput;
    }

    function create(ICowConditionalOrder.ConditionalOrderParams calldata params, bool dispatch) external;

    function domainSeparator() external view returns (bytes32);

    function isValidSafeSignature(
        address safe,
        address sender,
        bytes32 _hash,
        bytes32 _domainSeparator,
        bytes32 typeHash,
        bytes calldata encodeData,
        bytes calldata payload
    ) external view returns (bytes4);
}
