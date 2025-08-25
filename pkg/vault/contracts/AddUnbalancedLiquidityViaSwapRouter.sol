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
 * @notice Enable adding and removing liquidity unbalanced on pools that do not support it natively.
 * @dev This extends the standard `Router` in order to call shared internal hook implementation functions.
 * It factors out the unbalanced adds into two operations: a proportional add and a swap, executes them using
 * the standard router, then checks the limits.
 */
contract AddUnbalancedLiquidityViaSwapRouter is RouterHooks, IAddUnbalancedLiquidityViaSwapRouter {
    // Generalized SwapParams to accommodate both ExactIn and ExactOut.
    struct SwapParams {
        IERC20 tokenIn;
        IERC20 tokenOut;
        SwapKind kind;
        uint256 amountGiven;
        uint256 limit;
        bytes userData;
    }

    constructor(
        IVault vault,
        IPermit2 permit2,
        IWETH weth,
        string memory routerVersion
    ) RouterHooks(vault, weth, permit2, routerVersion) {
        // solhint-disable-previous-line no-empty-blocks
    }

    /// @inheritdoc IAddUnbalancedLiquidityViaSwapRouter
    function addUnbalancedLiquidityViaSwapExactIn(
        address pool,
        uint256 deadline,
        bool wethIsEth,
        AddLiquidityProportionalParams calldata addLiquidityParams,
        SwapExactInParams calldata swapParams
    ) external payable saveSenderAndManageEth returns (uint256[] memory amountsIn, uint256 swapAmountOut) {
        (amountsIn, swapAmountOut) = abi.decode(
            _vault.unlock(
                abi.encodeCall(
                    AddUnbalancedLiquidityViaSwapRouter.addUnbalancedLiquidityViaSwapHook,
                    _buildAddLiquidityParams(
                        pool,
                        msg.sender,
                        deadline,
                        wethIsEth,
                        addLiquidityParams,
                        _buildSwapExactInParams(swapParams)
                    )
                )
            ),
            (uint256[], uint256)
        );
    }

    /// @inheritdoc IAddUnbalancedLiquidityViaSwapRouter
    function addUnbalancedLiquidityViaSwapExactOut(
        address pool,
        uint256 deadline,
        bool wethIsEth,
        AddLiquidityProportionalParams calldata addLiquidityParams,
        SwapExactOutParams calldata swapParams
    ) external payable saveSenderAndManageEth returns (uint256[] memory amountsIn, uint256 swapAmountIn) {
        (amountsIn, swapAmountIn) = abi.decode(
            _vault.unlock(
                abi.encodeCall(
                    AddUnbalancedLiquidityViaSwapRouter.addUnbalancedLiquidityViaSwapHook,
                    _buildAddLiquidityParams(
                        pool,
                        msg.sender,
                        deadline,
                        wethIsEth,
                        addLiquidityParams,
                        _buildSwapExactOutParams(swapParams)
                    )
                )
            ),
            (uint256[], uint256)
        );
    }

    /***************************************************************************
                                   Queries
    ***************************************************************************/

    function queryAddUnbalancedLiquidityViaSwapExactIn(
        address pool,
        address sender,
        AddLiquidityProportionalParams calldata addLiquidityParams,
        SwapExactInParams calldata swapParams
    ) external saveSender(sender) returns (uint256[] memory amountsIn, uint256 swapAmountOut) {
        (amountsIn, swapAmountOut) = abi.decode(
            _vault.quote(
                abi.encodeCall(
                    AddUnbalancedLiquidityViaSwapRouter.queryAddUnbalancedLiquidityViaSwapHook,
                    _buildAddLiquidityParams(
                        pool,
                        address(this),
                        _MAX_AMOUNT, // No deadline in query
                        false, // wethIsEth is false in query
                        addLiquidityParams,
                        _buildSwapExactInParams(swapParams)
                    )
                )
            ),
            (uint256[], uint256)
        );
    }

    function queryAddUnbalancedLiquidityViaSwapExactOut(
        address pool,
        address sender,
        AddLiquidityProportionalParams calldata addLiquidityParams,
        SwapExactOutParams calldata swapParams
    ) external saveSender(sender) returns (uint256[] memory amountsIn, uint256 swapAmountIn) {
        (amountsIn, swapAmountIn) = abi.decode(
            _vault.quote(
                abi.encodeCall(
                    AddUnbalancedLiquidityViaSwapRouter.queryAddUnbalancedLiquidityViaSwapHook,
                    _buildAddLiquidityParams(
                        pool,
                        address(this),
                        _MAX_AMOUNT, // No deadline in query
                        false, // wethIsEth is false in query
                        addLiquidityParams,
                        _buildSwapExactOutParams(swapParams)
                    )
                )
            ),
            (uint256[], uint256)
        );
    }

    /***************************************************************************
                                   Hooks
    ***************************************************************************/

    function addUnbalancedLiquidityViaSwapHook(
        AddLiquidityAndSwapHookParams calldata params
    ) external nonReentrant onlyVault returns (uint256[] memory amountsIn, uint256 swapAmountCalculated) {
        (amountsIn, , ) = _addLiquidityHook(params.addLiquidityParams);
        swapAmountCalculated = _swapSingleTokenHook(params.swapParams);
    }

    function queryAddUnbalancedLiquidityViaSwapHook(
        AddLiquidityAndSwapHookParams calldata params
    ) external nonReentrant onlyVault returns (uint256[] memory amountsIn, uint256 swapAmountCalculated) {
        (amountsIn, , ) = _queryAddLiquidityHook(params.addLiquidityParams);
        swapAmountCalculated = _querySwapHook(params.swapParams);
    }

    /***************************************************************************
                                   Helper functions
    ***************************************************************************/

    // Required to avoid stack-too-deep in the caller.
    function _buildAddLiquidityParams(
        address pool,
        address sender,
        uint256 deadline,
        bool wethIsEth,
        AddLiquidityProportionalParams calldata addLiquidityParams,
        SwapParams memory swapParams
    ) private pure returns (AddLiquidityAndSwapHookParams memory params) {
        return
            AddLiquidityAndSwapHookParams({
                addLiquidityParams: AddLiquidityHookParams({
                    sender: sender,
                    pool: pool,
                    maxAmountsIn: addLiquidityParams.maxAmountsIn,
                    minBptAmountOut: addLiquidityParams.exactBptAmountOut,
                    kind: AddLiquidityKind.PROPORTIONAL,
                    wethIsEth: wethIsEth,
                    userData: addLiquidityParams.userData
                }),
                swapParams: SwapSingleTokenHookParams({
                    sender: sender,
                    kind: swapParams.kind,
                    pool: pool,
                    tokenIn: swapParams.tokenIn,
                    tokenOut: swapParams.tokenOut,
                    amountGiven: swapParams.amountGiven,
                    limit: swapParams.limit,
                    deadline: deadline,
                    wethIsEth: wethIsEth,
                    userData: swapParams.userData
                })
            });
    }

    function _buildSwapExactInParams(SwapExactInParams calldata swapParams) private pure returns (SwapParams memory) {
        return
            SwapParams({
                tokenIn: swapParams.tokenIn,
                tokenOut: swapParams.tokenOut,
                kind: SwapKind.EXACT_IN,
                amountGiven: swapParams.exactAmountIn,
                limit: swapParams.minAmountOut,
                userData: swapParams.userData
            });
    }

    function _buildSwapExactOutParams(SwapExactOutParams calldata swapParams) private pure returns (SwapParams memory) {
        return
            SwapParams({
                tokenIn: swapParams.tokenIn,
                tokenOut: swapParams.tokenOut,
                kind: SwapKind.EXACT_OUT,
                amountGiven: swapParams.exactAmountOut,
                limit: swapParams.maxAmountIn,
                userData: swapParams.userData
            });
    }
}
