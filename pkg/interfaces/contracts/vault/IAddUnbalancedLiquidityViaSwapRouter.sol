// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { AddLiquidityKind, RemoveLiquidityKind, SwapKind } from "./VaultTypes.sol";
import { IVault } from "./IVault.sol";
import "./RouterTypes.sol";

/// @notice Router interface for adding unbalanced liquidity via a combination of a proportional add and a swap.
interface IAddUnbalancedLiquidityViaSwapRouter {
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

    /**
     * @notice Adds liquidity to a pool with proportional token amounts and an ExactIn swap in the same transaction.
     * @param pool Address of the liquidity pool
     * @param deadline Timestamp after which the transaction will revert
     * @param wethIsEth If true, incoming ETH will be wrapped to WETH and outgoing WETH will be unwrapped to ETH
     * @param addLiquidityParams Parameters for adding liquidity
     * @param swapParams Parameters for the swap operation
     * @return amountsIn Array of amounts in for each token added to the pool
     * @return swapAmountOut Swap amount out for the swap operation
     */
    function addUnbalancedLiquidityViaSwapExactIn(
        address pool,
        uint256 deadline,
        bool wethIsEth,
        AddLiquidityProportionalParams calldata addLiquidityParams,
        SwapExactInParams calldata swapParams
    ) external payable returns (uint256[] memory amountsIn, uint256 swapAmountOut);

    /**
     * @notice Adds liquidity to a pool with proportional token amounts and an ExactOut swap in the same transaction.
     * @param pool Address of the liquidity pool
     * @param deadline Timestamp after which the transaction will revert
     * @param wethIsEth If true, incoming ETH will be wrapped to WETH and outgoing WETH will be unwrapped to ETH
     * @param addLiquidityParams Parameters for adding liquidity
     * @param swapParams Parameters for the swap operation
     * @return amountsIn Array of amounts in for each token added to the pool, sorted in token registration order.
     * @return swapAmountIn Swap amount in for the swap operation
     */
    function addUnbalancedLiquidityViaSwapExactOut(
        address pool,
        uint256 deadline,
        bool wethIsEth,
        AddLiquidityProportionalParams calldata addLiquidityParams,
        SwapExactOutParams calldata swapParams
    ) external payable returns (uint256[] memory amountsIn, uint256 swapAmountIn);

    /**
     * @notice Queries an `addUnbalancedLiquidityViaSwapExactIn` operation without actually executing it.
     * @param pool Address of the liquidity pool
     * @param sender The sender passed to the operation. It can influence results (e.g., with user-dependent hooks)
     * @param addLiquidityParams Parameters for adding liquidity
     * @param swapParams Parameters for the swap operation
     * @return amountsIn Array of amounts in for each token added to the pool
     * @return swapAmountOut Swap amount out for the swap operation
     */
    function queryAddUnbalancedLiquidityViaSwapExactIn(
        address pool,
        address sender,
        AddLiquidityProportionalParams calldata addLiquidityParams,
        SwapExactInParams calldata swapParams
    ) external returns (uint256[] memory amountsIn, uint256 swapAmountOut);

    /**
     * @notice Queries an `addUnbalancedLiquidityViaSwapExactOut` operation without actually executing it.
     * @param pool Address of the liquidity pool
     * @param sender The sender passed to the operation. It can influence results (e.g., with user-dependent hooks)
     * @param addLiquidityParams Parameters for adding liquidity
     * @param swapParams Parameters for the swap operation
     * @return amountsIn Array of amounts in for each token added to the pool
     * @return swapAmountIn Swap amount in for the swap operation
     */
    function queryAddUnbalancedLiquidityViaSwapExactOut(
        address pool,
        address sender,
        AddLiquidityProportionalParams calldata addLiquidityParams,
        SwapExactOutParams calldata swapParams
    ) external returns (uint256[] memory amountsIn, uint256 swapAmountIn);
}
