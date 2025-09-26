// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";

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
    using ArrayHelpers for *;

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
        (tokens, amountsIn) = _computeAddUnbalancedLiquidityViaSwap(hookParams);

        // In this case, the pools have two tokens,
        // but we use a 'for' loop instead of getting the needed indexes because it's simpler.
        for (uint256 i = 0; i < tokens.length; ++i) {
            _takeTokenIn(hookParams.sender, tokens[i], amountsIn[i], hookParams.wethIsEth);
        }

        _returnEth(hookParams.sender);
    }

    function queryAddUnbalancedLiquidityViaSwapHook(
        AddLiquidityAndSwapHookParams calldata params
    ) external nonReentrant onlyVault returns (uint256[] memory amountsIn) {
        (, amountsIn) = _computeAddUnbalancedLiquidityViaSwap(params);
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
    ) private returns (IERC20[] memory tokens, uint256[] memory amountsIn) {
        tokens = _vault.getPoolTokens(hookParams.pool);

        (uint256 exactTokenIndex, uint256 adjustableTokenIndex) = hookParams.operationParams.exactToken == tokens[0]
            ? (0, 1)
            : (1, 0);

        (amountsIn, , ) = _vault.addLiquidity(
            AddLiquidityParams({
                pool: hookParams.pool,
                to: hookParams.sender,
                maxAmountsIn: [_MAX_AMOUNT, _MAX_AMOUNT].toMemoryArray(),
                minBptAmountOut: hookParams.operationParams.minBptAmountOut,
                kind: AddLiquidityKind.PROPORTIONAL,
                userData: hookParams.operationParams.addLiquidityUserData
            })
        );

        uint256 limit = hookParams.operationParams.maxAdjustableAmount - amountsIn[adjustableTokenIndex];
        if (amountsIn[exactTokenIndex] > hookParams.operationParams.exactAmount) {
            uint256 swapAmount = amountsIn[exactTokenIndex] - hookParams.operationParams.exactAmount;

            (, uint256 swapAmountIn, uint256 swapAmountOut) = _vault.swap(
                VaultSwapParams({
                    kind: SwapKind.EXACT_OUT,
                    pool: hookParams.pool,
                    tokenIn: tokens[adjustableTokenIndex],
                    tokenOut: hookParams.operationParams.exactToken,
                    amountGivenRaw: swapAmount,
                    limitRaw: limit,
                    userData: hookParams.operationParams.swapUserData
                })
            );

            amountsIn[adjustableTokenIndex] += swapAmountIn;
            amountsIn[exactTokenIndex] -= swapAmountOut;
        } else if (amountsIn[exactTokenIndex] < hookParams.operationParams.exactAmount) {
            uint256 swapAmount = hookParams.operationParams.exactAmount - amountsIn[exactTokenIndex];

            (, uint256 swapAmountIn, uint256 swapAmountOut) = _vault.swap(
                VaultSwapParams({
                    kind: SwapKind.EXACT_IN,
                    pool: hookParams.pool,
                    tokenIn: hookParams.operationParams.exactToken,
                    tokenOut: tokens[adjustableTokenIndex],
                    amountGivenRaw: swapAmount,
                    limitRaw: limit,
                    userData: hookParams.operationParams.swapUserData
                })
            );

            amountsIn[exactTokenIndex] += swapAmountIn;
            amountsIn[adjustableTokenIndex] -= swapAmountOut;
        }

        if (amountsIn[exactTokenIndex] != hookParams.operationParams.exactAmount) {
            revert AmountInDoesNotMatchExact(amountsIn[exactTokenIndex], hookParams.operationParams.exactAmount);
        } else if (amountsIn[adjustableTokenIndex] > hookParams.operationParams.maxAdjustableAmount) {
            revert AmountInAboveMaxAdjustableAmount(
                amountsIn[adjustableTokenIndex],
                hookParams.operationParams.maxAdjustableAmount
            );
        }
    }
}
