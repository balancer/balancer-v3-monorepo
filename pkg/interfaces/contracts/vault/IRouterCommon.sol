// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IAllowanceTransfer } from "permit2/src/interfaces/IAllowanceTransfer.sol";
import { AddLiquidityKind, RemoveLiquidityKind } from "./VaultTypes.sol";

/// @notice Interface for funtions shared between the `Router` and `BatchRouter`.
interface IRouterCommon {
    /**
     * @notice Data for the add liquidity hook.
     * @param sender Account originating the add liquidity operation
     * @param pool Address of the liquidity pool
     * @param maxAmountsIn Maximum amounts of tokens to be added, sorted in token registration order
     * @param minBptAmountOut Minimum amount of pool tokens to be received
     * @param kind Type of join (e.g., single or multi-token)
     * @param wethIsEth If true, incoming ETH will be wrapped to WETH and outgoing WETH will be unwrapped to ETH
     * @param userData Additional (optional) data sent with the request to add liquidity
     */
    struct AddLiquidityHookParams {
        address sender;
        address pool;
        uint256[] maxAmountsIn;
        uint256 minBptAmountOut;
        AddLiquidityKind kind;
        bool wethIsEth;
        bytes userData;
    }

    /**
     * @notice Data for the remove liquidity hook.
     * @param sender Account originating the remove liquidity operation
     * @param pool Address of the liquidity pool
     * @param minAmountsOut Minimum amounts of tokens to be received, sorted in token registration order
     * @param maxBptAmountIn Maximum amount of pool tokens provided
     * @param kind Type of exit (e.g., single or multi-token)
     * @param wethIsEth If true, incoming ETH will be wrapped to WETH and outgoing WETH will be unwrapped to ETH
     * @param userData Additional (optional) data sent with the request to remove liquidity
     */
    struct RemoveLiquidityHookParams {
        address sender;
        address pool;
        uint256[] minAmountsOut;
        uint256 maxBptAmountIn;
        RemoveLiquidityKind kind;
        bool wethIsEth;
        bytes userData;
    }

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
