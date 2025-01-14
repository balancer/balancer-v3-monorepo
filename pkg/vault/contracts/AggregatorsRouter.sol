// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";
import { IAllowanceTransfer } from "permit2/src/interfaces/IAllowanceTransfer.sol";

import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";
import { IRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IRouter.sol";
import { IAggregatorsRouterRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IAggregatorsRouterRouter.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { RouterCommon } from "./RouterCommon.sol";

/**
 * @notice Entrypoint for aggregators who want make swaps without build in payment logic.
 * @dev The external API functions unlock the Vault, which calls back into the corresponding hook functions.
 * These interact with the Vault and settle accounting.
 */
contract AggregatorsRouter is IAggregatorsRouterRouter, RouterCommon {
    constructor(
        IVault vault,
        string memory routerVersion
    ) RouterCommon(vault, IWETH(address(0x00)), IPermit2(address(0x00)), routerVersion) {
        // solhint-disable-previous-line no-empty-blocks
    }

    /***************************************************************************
                                       Swaps
    ***************************************************************************/

    /// @inheritdoc IAggregatorsRouterRouter
    function swapSingleTokenExactIn(
        address pool,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 exactAmountIn,
        uint256 minAmountOut,
        uint256 deadline,
        bytes calldata userData
    ) external saveSender(msg.sender) returns (uint256) {
        return
            abi.decode(
                _vault.unlock(
                    abi.encodeCall(
                        AggregatorsRouter.swapSingleTokenHook,
                        IRouter.SwapSingleTokenHookParams({
                            sender: msg.sender,
                            kind: SwapKind.EXACT_IN,
                            pool: pool,
                            tokenIn: tokenIn,
                            tokenOut: tokenOut,
                            amountGiven: exactAmountIn,
                            limit: minAmountOut,
                            deadline: deadline,
                            wethIsEth: false,
                            userData: userData
                        })
                    )
                ),
                (uint256)
            );
    }

    /**
     * @notice Hook for swaps.
     * @dev Can only be called by the Vault.
    This router expects the caller to pay upfront by sending tokens to the vault directly, 
    so this call only accounts for the amount that has already been paid skipping transfers of any kind.
     * @param params Swap parameters (see IRouterSwap for struct definition)
     * @return amountCalculated Token amount calculated by the pool math (e.g., amountOut for a exact in swap)
     */
    function swapSingleTokenHook(
        IRouter.SwapSingleTokenHookParams calldata params
    ) external nonReentrant onlyVault returns (uint256) {
        (uint256 amountCalculated, uint256 amountIn, uint256 amountOut) = _swapHook(params);

        _vault.settle(params.tokenIn, amountIn);
        _sendTokenOut(params.sender, params.tokenOut, amountOut, false);

        return amountCalculated;
    }

    function _swapHook(
        IRouter.SwapSingleTokenHookParams calldata params
    ) internal returns (uint256 amountCalculated, uint256 amountIn, uint256 amountOut) {
        // The deadline is timestamp-based: it should not be relied upon for sub-minute accuracy.
        // solhint-disable-next-line not-rely-on-time
        if (block.timestamp > params.deadline) {
            revert SwapDeadline();
        }

        (amountCalculated, amountIn, amountOut) = _vault.swap(
            VaultSwapParams({
                kind: params.kind,
                pool: params.pool,
                tokenIn: params.tokenIn,
                tokenOut: params.tokenOut,
                amountGivenRaw: params.amountGiven,
                limitRaw: params.limit,
                userData: params.userData
            })
        );
    }

    /*******************************************************************************
                                      Queries
    *******************************************************************************/

    /// @inheritdoc IAggregatorsRouterRouter
    function querySwapSingleTokenExactIn(
        address pool,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 exactAmountIn,
        address sender,
        bytes memory userData
    ) external saveSender(sender) returns (uint256 amountCalculated) {
        return
            abi.decode(
                _vault.quote(
                    abi.encodeCall(
                        AggregatorsRouter.querySwapHook,
                        IRouter.SwapSingleTokenHookParams({
                            sender: msg.sender,
                            kind: SwapKind.EXACT_IN,
                            pool: pool,
                            tokenIn: tokenIn,
                            tokenOut: tokenOut,
                            amountGiven: exactAmountIn,
                            limit: 0,
                            deadline: _MAX_AMOUNT,
                            wethIsEth: false,
                            userData: userData
                        })
                    )
                ),
                (uint256)
            );
    }

    /**
     * @notice Hook for swap queries.
     * @dev Can only be called by the Vault. Also handles native ETH.
     * @param params Swap parameters (see IRouter for struct definition)
     * @return amountCalculated Token amount calculated by the pool math (e.g., amountOut for a exact in swap)
     */
    function querySwapHook(
        IRouter.SwapSingleTokenHookParams calldata params
    ) external nonReentrant onlyVault returns (uint256) {
        (uint256 amountCalculated, , ) = _swapHook(params);

        return amountCalculated;
    }

    /***************************************************************************
                                       Overrides
    ***************************************************************************/
    function permitBatchAndCall(
        PermitApproval[] calldata,
        bytes[] calldata,
        IAllowanceTransfer.PermitBatch calldata,
        bytes calldata,
        bytes[] calldata
    ) external payable override returns (bytes[] memory) {
        revert OperationNotSupported("permit2 is not supported");
    }
}
