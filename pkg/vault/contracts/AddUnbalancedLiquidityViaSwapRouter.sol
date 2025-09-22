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

            _takeTokenIn(hookParams.sender, tokens[i], amountIn, hookParams.wethIsEth);
            _sendTokenOut(hookParams.sender, tokens[i], amountOut, hookParams.wethIsEth);
        }
        _returnEth(hookParams.sender);
    }

    function queryAddUnbalancedLiquidityViaSwapHook(
        AddLiquidityAndSwapHookParams calldata params
    ) external nonReentrant onlyVault returns (uint256[] memory amountsIn) {
        (, amountsIn, ) = _computeAddUnbalancedLiquidityViaSwap(params);
    }

    /**
     * @notice Executes unbalanced liquidity addition by combining a proportional add and a "adjustment" swap.
     * @dev We require an exact amount in of one token, and designate another "adjustable" token whose contribution
     * can differ from strict proportionality in order to guarantee an exact amount of `exactToken`.
     *
     * Strategy:
     * 1. Perform a proportional add using the add liquidity parameters.
     * 2. Check whether the actual `exactToken` contribution matches the target amount.
     * 3. If not, perform a corrective swap using the adjustable token to make it match.
     * 4. All other tokens remain at their proportional amounts.
     * 
     * Case 1 - Proportional add contributed too much `exactToken`
     * - EXACT_OUT swap of `adjustableToken` for `exactToken`: add more of the adjustable token to return the excess
     * - Limit check: Ensure total amount of `adjustableToken` doesn't exceed maxAmountIn
     * 
     * Case 2 - Proportional add contributed too little `exactToken`
     * - EXACT_IN swap of `exactToken` for `adjustableToken`: remove some adjustable token to make up the deficit
     * - No limit check needed: we're returning `adjustableToken`, not taking more
     * 
     * Final result: Net contribution of `exactToken` exactly equals exactAmountIn
     */
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
            if (address(tokens[i]) == address(hookParams.operationParams.exactToken)) {
                exactInTokenIndex = i;
            } else if (address(tokens[i]) == address(hookParams.operationParams.adjustableToken)) {
                exactMaxInTokenIndex = i;
            }
        }

        if (amountsIn[exactInTokenIndex] > hookParams.operationParams.exactAmount) {
            uint256 swapAmount = amountsIn[exactInTokenIndex] - hookParams.operationParams.exactAmount;

            (, uint256 swapAmountIn, uint256 swapAmountOut) = _vault.swap(
                VaultSwapParams({
                    kind: SwapKind.EXACT_OUT,
                    pool: hookParams.pool,
                    tokenIn: hookParams.operationParams.adjustableToken,
                    tokenOut: hookParams.operationParams.exactToken,
                    amountGivenRaw: swapAmount,
                    limitRaw: hookParams.operationParams.maxAdjustableAmount - amountsIn[exactMaxInTokenIndex],
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
        } else if (amountsIn[exactInTokenIndex] < hookParams.operationParams.exactAmount) {
            uint256 swapAmount = hookParams.operationParams.exactAmount - amountsIn[exactInTokenIndex];
            (, uint256 swapAmountIn, uint256 swapAmountOut) = _vault.swap(
                VaultSwapParams({
                    kind: SwapKind.EXACT_IN,
                    pool: hookParams.pool,
                    tokenIn: hookParams.operationParams.exactToken,
                    tokenOut: hookParams.operationParams.adjustableToken,
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
