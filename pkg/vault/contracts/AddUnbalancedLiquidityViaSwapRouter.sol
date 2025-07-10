// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";

import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import {
    IAddUnbalancedLiquidityViaSwapRouter
} from "@balancer-labs/v3-interfaces/contracts/vault/IAddUnbalancedLiquidityViaSwapRouter.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/RouterTypes.sol";

import { RouterHooks } from "./RouterHooks.sol";

/**
 * @notice Entrypoint for add unbalanced liquidity via swap operations.
 * @dev Some pools don’t support non-proportional liquidity addition. This router helps to bypass that limitation.
 */
contract AddUnbalancedLiquidityViaSwapRouter is RouterHooks, IAddUnbalancedLiquidityViaSwapRouter {
    constructor(
        IVault vault,
        IPermit2 permit2,
        string memory routerVersion
    ) RouterHooks(vault, IWETH(address(0)), permit2, routerVersion) {
        // solhint-disable-previous-line no-empty-blocks
    }

    /// @inheritdoc IAddUnbalancedLiquidityViaSwapRouter
    function addUnbalancedLiquidityViaSwapExactIn(
        address pool,
        uint256 deadline,
        AddLiquidityProportionalParams calldata addLiquidityParams,
        SwapExactInParams calldata swapParams
    )
        external
        saveSender(msg.sender)
        returns (
            uint256[] memory addLiquidityAmountsIn,
            uint256 addLiquidityBptAmountOut,
            uint256 swapAmountOut,
            bytes memory addLiquidityReturnData
        )
    {
        return
            abi.decode(
                _vault.unlock(
                    abi.encodeCall(
                        AddUnbalancedLiquidityViaSwapRouter.addUnbalancedLiquidityViaSwapHook,
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
                                kind: SwapKind.EXACT_IN,
                                pool: pool,
                                tokenIn: swapParams.tokenIn,
                                tokenOut: swapParams.tokenOut,
                                amountGiven: swapParams.exactAmountIn,
                                limit: swapParams.minAmountOut,
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

    /// @inheritdoc IAddUnbalancedLiquidityViaSwapRouter
    function addUnbalancedLiquidityViaSwapExactOut(
        address pool,
        uint256 deadline,
        AddLiquidityProportionalParams calldata addLiquidityParams,
        SwapExactOutParams calldata swapParams
    )
        external
        saveSender(msg.sender)
        returns (
            uint256[] memory addLiquidityAmountsIn,
            uint256 addLiquidityBptAmountOut,
            uint256 swapAmountIn,
            bytes memory addLiquidityReturnData
        )
    {
        return
            abi.decode(
                _vault.unlock(
                    abi.encodeCall(
                        AddUnbalancedLiquidityViaSwapRouter.addUnbalancedLiquidityViaSwapHook,
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
                                kind: SwapKind.EXACT_OUT,
                                pool: pool,
                                tokenIn: swapParams.tokenIn,
                                tokenOut: swapParams.tokenOut,
                                amountGiven: swapParams.exactAmountOut,
                                limit: swapParams.maxAmountIn,
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

    /// @inheritdoc IAddUnbalancedLiquidityViaSwapRouter
    function queryAddUnbalancedLiquidityViaSwapExactIn(
        address pool,
        address sender,
        AddLiquidityProportionalParams calldata addLiquidityParams,
        SwapExactInParams calldata swapParams
    )
        external
        saveSender(sender)
        returns (
            uint256[] memory addLiquidityAmountsIn,
            uint256 addLiquidityBptAmountOut,
            uint256 swapAmountOut,
            bytes memory addLiquidityReturnData
        )
    {
        return
            abi.decode(
                _vault.quote(
                    abi.encodeCall(
                        AddUnbalancedLiquidityViaSwapRouter.queryAddUnbalancedLiquidityViaSwapHook,
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
                                kind: SwapKind.EXACT_IN,
                                pool: pool,
                                tokenIn: swapParams.tokenIn,
                                tokenOut: swapParams.tokenOut,
                                amountGiven: swapParams.exactAmountIn,
                                limit: swapParams.minAmountOut,
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

    /// @inheritdoc IAddUnbalancedLiquidityViaSwapRouter
    function queryAddUnbalancedLiquidityViaSwapExactOut(
        address pool,
        address sender,
        AddLiquidityProportionalParams calldata addLiquidityParams,
        SwapExactOutParams calldata swapParams
    )
        external
        saveSender(sender)
        returns (
            uint256[] memory addLiquidityAmountsIn,
            uint256 addLiquidityBptAmountOut,
            uint256 swapAmountIn,
            bytes memory addLiquidityReturnData
        )
    {
        return
            abi.decode(
                _vault.quote(
                    abi.encodeCall(
                        AddUnbalancedLiquidityViaSwapRouter.queryAddUnbalancedLiquidityViaSwapHook,
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
                                kind: SwapKind.EXACT_OUT,
                                pool: pool,
                                tokenIn: swapParams.tokenIn,
                                tokenOut: swapParams.tokenOut,
                                amountGiven: swapParams.exactAmountOut,
                                limit: swapParams.maxAmountIn,
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

    function addUnbalancedLiquidityViaSwapHook(
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

    function queryAddUnbalancedLiquidityViaSwapHook(
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
