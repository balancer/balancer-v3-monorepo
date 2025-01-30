// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { ICowConditionalOrder } from "./ICowConditionalOrder.sol";

/// @notice Utility contract used to validate orders in the `CowSwapFeeBurner`.
interface IComposableCow {
    /**
     * @notice Data passed to ComposableCoW via the payload parameter of isValidSafeSignature.
     * @dev See github.com/curvefi/curve-burners/blob/main/contracts/burners/CowSwapBurner.vy#L66:L69.
     * @param proof Merkle Tree proof
     * @param params Conditional order params
     * @param offchainInput Off-chain input (similar to Balancer `userData`); currently unused
     */
    struct Payload {
        bytes32[] proof;
        ICowConditionalOrder.ConditionalOrderParams params;
        bytes offchainInput;
    }

    /**
     * @notice Construct a CoW order.
     * @param params Order parameters
     * @param dispatch If true, submit the order (always true in the CowSwapBurner)
     */
    function create(ICowConditionalOrder.ConditionalOrderParams calldata params, bool dispatch) external;

    function domainSeparator() external view returns (bytes32);

    /// @notice Delegated ERC-1271 signature validation with an enhanced context.
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
