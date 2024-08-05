// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IAllowanceTransfer } from "permit2/src/interfaces/IAllowanceTransfer.sol";

/// @notice Interface for funtions shared between the `Router` and `BatchRouter`.
interface IRouterCommon {
    /**
     * @notice Get the first sender which initialized the call to Router.
     * @return address The sender address
     */
    function getSender() external view returns (address);

    /*******************************************************************************
                                         Utils
    *******************************************************************************/

    struct PermitApproval {
        address token;
        address owner;
        address spender;
        uint256 amount;
        uint256 nonce;
        uint256 deadline;
    }

    /**
     * @notice Permits multiple allowances and executes a batch of function calls on this contract.
     * @param permitBatch An array of `PermitApproval` structs, each representing an ERC20 permit request
     * @param permitSignatures An array of bytes, corresponding to the permit request signature in `permitBatch`
     * @param permit2Batch A batch of permit2 approvals
     * @param permit2Signature A permit2 signature for the batch approval
     * @param multicallData An array of bytes arrays, each representing an encoded function call on this contract
     * @return results Array of bytes arrays, each representing the return data from each function call executed
     */
    function permitBatchAndCall(
        PermitApproval[] calldata permitBatch,
        bytes[] calldata permitSignatures,
        IAllowanceTransfer.PermitBatch calldata permit2Batch,
        bytes calldata permit2Signature,
        bytes[] calldata multicallData
    ) external payable returns (bytes[] memory results);

    /**
     * @notice Executes a batch of function calls on this contract.
     * @param data Encoded function calls to be executed in the batch.
     * @return results Array of bytes arrays, each representing the return data from each function call executed.
     */
    function multicall(bytes[] calldata data) external returns (bytes[] memory results);
}
