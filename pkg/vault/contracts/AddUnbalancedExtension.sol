// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";

import { IBatchRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IBatchRouter.sol";
import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { EVMCallModeHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/EVMCallModeHelpers.sol";
import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import {
    TransientEnumerableSet
} from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/TransientEnumerableSet.sol";
import {
    TransientStorageHelpers
} from "@balancer-labs/v3-solidity-utils/contracts/helpers/TransientStorageHelpers.sol";

import { Router } from "./Router.sol";
import { BatchRouterCommon } from "./BatchRouterCommon.sol";

contract AddUnbalancedExtension is Router {
    struct AddLiquidityProportionalParams {
        uint256[] maxAmountsIn;
        uint256 exactBptAmountOut;
        bytes userData;
    }

    struct SwapExactInParams {
        IERC20 tokenIn;
        IERC20 tokenOut;
        uint256 exactAmountIn;
        uint256 minAmountOut;
        bytes userData;
    }

    struct SwapExactOutParams {
        IERC20 tokenIn;
        IERC20 tokenOut;
        uint256 exactAmountOut;
        uint256 maxAmountIn;
        bytes userData;
    }

    struct AddLiquidityAndSwapHookParams {
        AddLiquidityHookParams addLiquidityParams;
        SwapSingleTokenHookParams swapParams;
    }

    constructor(
        IVault vault,
        IWETH weth,
        IPermit2 permit2,
        string memory routerVersion
    ) Router(vault, weth, permit2, routerVersion) {
        // solhint-disable-previous-line no-empty-blocks
    }

    function addProportionalAndSwapExactIn(
        address pool,
        uint256 deadline,
        AddLiquidityProportionalParams calldata addLiquidityParams,
        SwapExactInParams calldata swapParams
    )
        external
        payable
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
                        AddUnbalancedExtension.addProportionalAndSwapHook,
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

    function addProportionalAndSwapExactOut(
        address pool,
        uint256 deadline,
        AddLiquidityProportionalParams calldata addLiquidityParams,
        SwapExactOutParams calldata swapParams
    )
        external
        payable
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
                        AddUnbalancedExtension.addProportionalAndSwapHook,
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

    function queryAddProportionalAndSwapExactIn(
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
                        AddUnbalancedExtension.addProportionalAndSwapHook,
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

    function queryAddProportionalAndSwapExactOut(
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
                        AddUnbalancedExtension.addProportionalAndSwapHook,
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
        payable
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
}
