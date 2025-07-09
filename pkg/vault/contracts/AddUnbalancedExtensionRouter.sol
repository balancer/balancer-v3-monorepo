// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";

import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import {
    SwapKind,
    AddLiquidityKind,
    RemoveLiquidityKind
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { Router } from "./Router.sol";

/**
 * @notice Enable adding and removing liquidity unbalanced on pools that do not support it natively.
 * @dev This extends the standard `Router` in order to call shared internal hook implementation functions.
 * It factors out the unbalanced adds into two operations: a proportional add and a swap, executes them using
 * the standard router, then checks the limits.
 * 
 * It does not support operations on native ETH.
 */
contract AddUnbalancedExtensionRouter is Router {
    struct AddLiquidityProportionalParams {
        uint256[] maxAmountsIn;
        uint256 exactBptAmountOut;
        bytes userData;
    }

    struct SwapParams {
        IERC20 tokenIn;
        IERC20 tokenOut;
        SwapKind kind;
        uint256 amountGiven;
        uint256 limit;
        bytes userData;
    }

    struct AddLiquidityAndSwapHookParams {
        AddLiquidityHookParams addLiquidityParams;
        SwapSingleTokenHookParams swapParams;
    }

    constructor(
        IVault vault,
        IPermit2 permit2,
        string memory routerVersion
    ) Router(vault, IWETH(address(0)), permit2, routerVersion) {
        // solhint-disable-previous-line no-empty-blocks
    }

    function addProportionalAndSwap(
        address pool,
        uint256 deadline,
        AddLiquidityProportionalParams calldata addLiquidityParams,
        SwapParams calldata swapParams
    )
        external
        saveSender(msg.sender)
        returns (
            uint256[] memory addLiquidityAmountsIn,
            uint256 addLiquidityBptAmountOut,
            uint256 swapAmountCalculated,
            bytes memory addLiquidityReturnData
        )
    {
        return
            abi.decode(
                _vault.unlock(
                    abi.encodeCall(
                        AddUnbalancedExtensionRouter.addProportionalAndSwapHook,
                        AddLiquidityAndSwapHookParams({
                            addLiquidityParams: AddLiquidityHookParams({
                                sender: msg.sender,
                                pool: pool,
                                maxAmountsIn: addLiquidityParams.maxAmountsIn,
                                minBptAmountOut: addLiquidityParams.exactBptAmountOut,
                                kind: AddLiquidityKind.PROPORTIONAL,
                                wethIsEth: false,
                                userData: addLiquidityParams.userData
                            }),
                            swapParams: SwapSingleTokenHookParams({
                                sender: msg.sender,
                                kind: swapParams.kind,
                                pool: pool,
                                tokenIn: swapParams.tokenIn,
                                tokenOut: swapParams.tokenOut,
                                amountGiven: swapParams.amountGiven,
                                limit: swapParams.limit,
                                deadline: deadline,
                                wethIsEth: false,
                                userData: swapParams.userData
                            })
                        })
                    )
                ),
                (uint256[], uint256, uint256, bytes)
            );
    }

    function queryAddProportionalAndSwap(
        address pool,
        address sender,
        AddLiquidityProportionalParams calldata addLiquidityParams,
        SwapParams calldata swapParams
    )
        external
        saveSender(sender)
        returns (
            uint256[] memory addLiquidityAmountsIn,
            uint256 addLiquidityBptAmountOut,
            uint256 swapAmountCalculated,
            bytes memory addLiquidityReturnData
        )
    {
        return
            abi.decode(
                _vault.quote(
                    abi.encodeCall(
                        AddUnbalancedExtensionRouter.queryAddProportionalAndSwapHook,
                        AddLiquidityAndSwapHookParams({
                            addLiquidityParams: AddLiquidityHookParams({
                                sender: address(this),
                                pool: pool,
                                maxAmountsIn: addLiquidityParams.maxAmountsIn,
                                minBptAmountOut: addLiquidityParams.exactBptAmountOut,
                                kind: AddLiquidityKind.PROPORTIONAL,
                                wethIsEth: false,
                                userData: addLiquidityParams.userData
                            }),
                            swapParams: SwapSingleTokenHookParams({
                                sender: address(this),
                                kind: swapParams.kind,
                                pool: pool,
                                tokenIn: swapParams.tokenIn,
                                tokenOut: swapParams.tokenOut,
                                amountGiven: swapParams.amountGiven,
                                limit: swapParams.limit,
                                deadline: _MAX_AMOUNT,
                                wethIsEth: false,
                                userData: swapParams.userData
                            })
                        })
                    )
                ),
                (uint256[], uint256, uint256, bytes)
            );
    }

    function addProportionalAndSwapHook(
        AddLiquidityAndSwapHookParams calldata params
    )
        external
        nonReentrant
        onlyVault
        returns (
            uint256[] memory addLiquidityAmountsIn,
            uint256 addLiquidityBptAmountOut,
            uint256 swapAmountCalculated,
            bytes memory addLiquidityReturnData
        )
    {
        (addLiquidityAmountsIn, addLiquidityBptAmountOut, addLiquidityReturnData) = _addLiquidityHook(
            params.addLiquidityParams
        );
        swapAmountCalculated = _swapSingleTokenHook(params.swapParams);
    }

    function queryAddProportionalAndSwapHook(
        AddLiquidityAndSwapHookParams calldata params
    )
        external
        nonReentrant
        onlyVault
        returns (
            uint256[] memory addLiquidityAmountsIn,
            uint256 addLiquidityBptAmountOut,
            uint256 swapAmountCalculated,
            bytes memory addLiquidityReturnData
        )
    {
        (addLiquidityAmountsIn, addLiquidityBptAmountOut, addLiquidityReturnData) = _queryAddLiquidityHook(
            params.addLiquidityParams
        );
        swapAmountCalculated = _querySwapHook(params.swapParams);
    }
}
