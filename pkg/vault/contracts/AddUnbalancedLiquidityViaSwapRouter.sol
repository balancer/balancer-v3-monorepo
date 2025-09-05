// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/console.sol";
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
    function addUnbalancedLiquidityViaSwap(
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

    function queryAddUnbalancedLiquidityViaSwap(
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
        uint256[] memory amountsOut;
        (tokens, amountsIn, amountsOut) = _computeAddUnbalancedLiquidityViaSwap(hookParams);
        for (uint256 i = 0; i < tokens.length; ++i) {
            uint256 amountIn = amountsIn[i];
            uint256 amountOut = amountsOut[i];

            console.log("take token in", amountIn);
            _takeTokenIn(hookParams.sender, tokens[i], amountIn, hookParams.wethIsEth);

            console.log("send token out", amountOut);
            _sendTokenOut(hookParams.sender, tokens[i], amountOut, hookParams.wethIsEth);
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
    ) private returns (IERC20[] memory tokens, uint256[] memory amountsIn, uint256[] memory amountsOut) {
        (amountsIn, , ) = _vault.addLiquidity(
            AddLiquidityParams({
                pool: hookParams.pool,
                to: hookParams.sender,
                maxAmountsIn: hookParams.operationParams.proportionalMaxAmountsIn,
                minBptAmountOut: hookParams.operationParams.exactProportionalBptAmountOut,
                kind: AddLiquidityKind.PROPORTIONAL,
                userData: hookParams.operationParams.addLiquidityUserData
            })
        );

        amountsOut = new uint256[](amountsIn.length);

        // maxAmountsIn length is checked against tokens length at the Vault.
        tokens = _vault.getPoolTokens(hookParams.pool);

        // Find token index
        uint256 exactInTokenIndex;
        uint256 exactMaxInTokenIndex;
        for (uint256 i = 0; i < tokens.length; i++) {
            if (address(tokens[i]) == address(hookParams.operationParams.tokenExactIn)) {
                exactInTokenIndex = i;
            } else if (address(tokens[i]) == address(hookParams.operationParams.tokenMaxIn)) {
                exactMaxInTokenIndex = i;
            }
        }

        if (amountsIn[exactInTokenIndex] > hookParams.operationParams.exactAmountIn) {
            uint256 swapAmount = amountsIn[exactInTokenIndex] - hookParams.operationParams.exactAmountIn;

            (, uint256 swapAmountIn, uint256 swapAmountOut) = _vault.swap(
                VaultSwapParams({
                    kind: SwapKind.EXACT_OUT,
                    pool: hookParams.pool,
                    tokenIn: hookParams.operationParams.tokenMaxIn,
                    tokenOut: hookParams.operationParams.tokenExactIn,
                    amountGivenRaw: swapAmount,
                    limitRaw: amountsIn[exactMaxInTokenIndex],
                    userData: hookParams.operationParams.swapUserData
                })
            );

            amountsIn[exactMaxInTokenIndex] += swapAmountIn;
            if (amountsIn[exactInTokenIndex] >= swapAmountOut) {
                amountsIn[exactInTokenIndex] -= swapAmountOut;
            } else {
                amountsIn[exactInTokenIndex] = 0;
                amountsOut[exactInTokenIndex] = swapAmountOut - amountsIn[exactInTokenIndex];
            }
        } else if (amountsIn[exactInTokenIndex] < hookParams.operationParams.exactAmountIn) {
            uint256 swapAmount = hookParams.operationParams.exactAmountIn - amountsIn[exactInTokenIndex];
            (, uint256 swapAmountIn, uint256 swapAmountOut) = _vault.swap(
                VaultSwapParams({
                    kind: SwapKind.EXACT_IN,
                    pool: hookParams.pool,
                    tokenIn: hookParams.operationParams.tokenExactIn,
                    tokenOut: hookParams.operationParams.tokenMaxIn,
                    amountGivenRaw: swapAmount,
                    limitRaw: 0,
                    userData: hookParams.operationParams.swapUserData
                })
            );

            amountsIn[exactInTokenIndex] += swapAmountIn;
            if (amountsIn[exactMaxInTokenIndex] >= swapAmountOut) {
                amountsIn[exactMaxInTokenIndex] -= swapAmountOut;
            } else {
                amountsOut[exactMaxInTokenIndex] = swapAmountOut - amountsIn[exactMaxInTokenIndex];
                amountsIn[exactMaxInTokenIndex] = 0;
            }
        }
    }
}
