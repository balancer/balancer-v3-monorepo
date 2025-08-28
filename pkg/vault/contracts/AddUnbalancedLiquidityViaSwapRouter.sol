// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";

import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import {
    IAddUnbalancedLiquidityViaSwapRouter
} from "@balancer-labs/v3-interfaces/contracts/vault/IAddUnbalancedLiquidityViaSwapRouter.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/RouterTypes.sol";

import { RouterQueries } from "./RouterQueries.sol";

/**
 * @notice Enable adding and removing liquidity unbalanced on pools that do not support it natively.
 * @dev This extends the standard `Router` in order to call shared internal hook implementation functions.
 * It factors out the unbalanced adds into two operations: a proportional add and a swap, executes them using
 * the standard router, then checks the limits.
 */
contract AddUnbalancedLiquidityViaSwapRouter is RouterQueries, IAddUnbalancedLiquidityViaSwapRouter {
    constructor(
        IVault vault,
        IPermit2 permit2,
        IWETH weth,
        string memory routerVersion
    ) RouterQueries(vault, weth, permit2, routerVersion) {
        // solhint-disable-previous-line no-empty-blocks
    }

    /// @inheritdoc IAddUnbalancedLiquidityViaSwapRouter
    function addUnbalancedLiquidityViaSwapExactIn(
        address pool,
        uint256 deadline,
        bool wethIsEth,
        AddLiquidityAndSwapParams calldata params
    ) external payable saveSender(msg.sender) returns (uint256[] memory amountsIn) {
        return
            abi.decode(
                _vault.unlock(
                    abi.encodeCall(
                        AddUnbalancedLiquidityViaSwapRouter.addUnbalancedLiquidityViaSwapHook,
                        AddLiquidityAndSwapHookParams({
                            pool: pool,
                            sender: msg.sender,
                            deadline: deadline,
                            wethIsEth: wethIsEth,
                            swapKind: SwapKind.EXACT_IN,
                            operationParams: params
                        })
                    )
                ),
                (uint256[])
            );
    }

    /// @inheritdoc IAddUnbalancedLiquidityViaSwapRouter
    function addUnbalancedLiquidityViaSwapExactOut(
        address pool,
        uint256 deadline,
        bool wethIsEth,
        AddLiquidityAndSwapParams calldata params
    ) external payable saveSender(msg.sender) returns (uint256[] memory amountsIn) {
        return
            abi.decode(
                _vault.unlock(
                    abi.encodeCall(
                        AddUnbalancedLiquidityViaSwapRouter.addUnbalancedLiquidityViaSwapHook,
                        AddLiquidityAndSwapHookParams({
                            pool: pool,
                            sender: msg.sender,
                            deadline: deadline,
                            wethIsEth: wethIsEth,
                            swapKind: SwapKind.EXACT_OUT,
                            operationParams: params
                        })
                    )
                ),
                (uint256[])
            );
    }

    /***************************************************************************
                                   Queries
    ***************************************************************************/

    function queryAddUnbalancedLiquidityViaSwapExactIn(
        address pool,
        address sender,
        AddLiquidityAndSwapParams calldata params
    ) external saveSender(sender) returns (uint256[] memory amountsIn) {
        return
            abi.decode(
                _vault.quote(
                    abi.encodeCall(
                        AddUnbalancedLiquidityViaSwapRouter.queryAddUnbalancedLiquidityViaSwapHook,
                        AddLiquidityAndSwapHookParams({
                            pool: pool,
                            sender: address(this), // Queries use the router as the sender
                            deadline: _MAX_AMOUNT, // Queries do not have deadlines
                            wethIsEth: false, // wethIsEth is false for queries
                            swapKind: SwapKind.EXACT_IN,
                            operationParams: params
                        })
                    )
                ),
                (uint256[])
            );
    }

    function queryAddUnbalancedLiquidityViaSwapExactOut(
        address pool,
        address sender,
        AddLiquidityAndSwapParams calldata params
    ) external saveSender(sender) returns (uint256[] memory amountsIn) {
        return
            abi.decode(
                _vault.quote(
                    abi.encodeCall(
                        AddUnbalancedLiquidityViaSwapRouter.queryAddUnbalancedLiquidityViaSwapHook,
                        AddLiquidityAndSwapHookParams({
                            pool: pool,
                            sender: address(this), // Queries use the router as the sender
                            deadline: _MAX_AMOUNT, // Queries do not have deadlines
                            wethIsEth: false, // wethIsEth is false for queries
                            swapKind: SwapKind.EXACT_OUT,
                            operationParams: params
                        })
                    )
                ),
                (uint256[])
            );
    }

    /***************************************************************************
                                   Hooks
    ***************************************************************************/

    function addUnbalancedLiquidityViaSwapHook(
        AddLiquidityAndSwapHookParams calldata hookParams
    ) external nonReentrant onlyVault returns (uint256[] memory amountsIn) {
        // The deadline is timestamp-based: it should not be relied upon for sub-minute accuracy.
        // solhint-disable-next-line not-rely-on-time
        if (block.timestamp > hookParams.deadline) {
            revert SwapDeadline();
        }

        IERC20[] memory tokens;
        uint256 swapAmountOut;
        (tokens, amountsIn, swapAmountOut) = _computeAddUnbalancedLiquidityViaSwap(hookParams);

        for (uint256 i = 0; i < tokens.length; ++i) {
            uint256 amountIn = amountsIn[i];
            if (amountIn == 0) {
                continue;
            }

            console.log("takeTokenIn", address(tokens[i]), amountIn);
            _takeTokenIn(hookParams.sender, tokens[i], amountIn, hookParams.wethIsEth);
        }

        _returnEth(hookParams.sender);
    }

    function queryAddUnbalancedLiquidityViaSwapHook(
        AddLiquidityAndSwapHookParams calldata params
    ) external nonReentrant onlyVault returns (uint256[] memory amountsIn) {
        (, amountsIn, ) = _computeAddUnbalancedLiquidityViaSwap(params);
    }

    function _computeAddUnbalancedLiquidityViaSwap(
        AddLiquidityAndSwapHookParams calldata hookParams
    ) private returns (IERC20[] memory tokens, uint256[] memory amountsIn, uint256 swapAmountOut) {
        (amountsIn, , ) = _vault.addLiquidity(
            AddLiquidityParams({
                pool: hookParams.pool,
                to: hookParams.sender,
                maxAmountsIn: hookParams.operationParams.maxAmountsIn,
                minBptAmountOut: hookParams.operationParams.exactBptAmountOut,
                kind: AddLiquidityKind.PROPORTIONAL,
                userData: bytes("")
            })
        );

        // maxAmountsIn length is checked against tokens length at the Vault.
        tokens = _vault.getPoolTokens(hookParams.pool);

        // Find token index
        uint256 tokenInIndex;
        uint256 tokenOutIndex;
        for (uint256 i = 0; i < tokens.length; i++) {
            if (address(tokens[i]) == address(hookParams.operationParams.swapTokenIn)) {
                tokenInIndex = i;
            } else if (address(tokens[i]) == address(hookParams.operationParams.swapTokenOut)) {
                tokenOutIndex = i;
            }
        }

        uint256 swapAmountIn;
        (, swapAmountIn, swapAmountOut) = _vault.swap(
            VaultSwapParams({
                kind: hookParams.swapKind,
                pool: hookParams.pool,
                tokenIn: hookParams.operationParams.swapTokenIn,
                tokenOut: hookParams.operationParams.swapTokenOut,
                amountGivenRaw: hookParams.operationParams.swapAmountGiven,
                limitRaw: hookParams.operationParams.swapLimit,
                userData: bytes("")
            })
        );

        amountsIn[tokenInIndex] += swapAmountIn;
        amountsIn[tokenOutIndex] -= swapAmountOut;
    }
}
