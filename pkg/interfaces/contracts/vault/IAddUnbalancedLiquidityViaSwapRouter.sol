// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./RouterTypes.sol";

/// @notice Router interface for adding unbalanced liquidity via a combination of a proportional add and a swap.
interface IAddUnbalancedLiquidityViaSwapRouter {
    struct AddLiquidityAndSwapParams {
        uint256[] maxAmountsIn;
        uint256 exactBptAmountOut;
        IERC20 swapTokenIn;
        IERC20 swapTokenOut;
        uint256 swapAmountGiven;
        uint256 swapLimit;
    }

    struct AddLiquidityAndSwapHookParams {
        address pool;
        address sender;
        uint256 deadline;
        bool wethIsEth;
        SwapKind swapKind;
        AddLiquidityAndSwapParams operationParams;
    }

    /**
     * @notice Adds liquidity to a pool with proportional token amounts and an ExactIn swap in the same transaction.
     * @param pool Address of the liquidity pool
     * @param deadline Timestamp after which the transaction will revert
     * @param wethIsEth If true, incoming ETH will be wrapped to WETH and outgoing WETH will be unwrapped to ETH
     * @param params Parameters for the add liquidity and swap operation
     * @return amountsIn Array of amounts in for each token added to the pool, sorted in token registration order.
     */
    function addUnbalancedLiquidityViaSwapExactIn(
        address pool,
        uint256 deadline,
        bool wethIsEth,
        AddLiquidityAndSwapParams calldata params
    ) external payable returns (uint256[] memory amountsIn);

    /**
     * @notice Adds liquidity to a pool with proportional token amounts and an ExactOut swap in the same transaction.
     * @param pool Address of the liquidity pool
     * @param deadline Timestamp after which the transaction will revert
     * @param wethIsEth If true, incoming ETH will be wrapped to WETH and outgoing WETH will be unwrapped to ETH
     * @param params Parameters for the add liquidity and swap operation
     * @return amountsIn Array of amounts in for each token added to the pool, sorted in token registration order.
     */
    function addUnbalancedLiquidityViaSwapExactOut(
        address pool,
        uint256 deadline,
        bool wethIsEth,
        AddLiquidityAndSwapParams calldata params
    ) external payable returns (uint256[] memory amountsIn);

    /**
     * @notice Queries an `addUnbalancedLiquidityViaSwapExactIn` operation without actually executing it.
     * @param pool Address of the liquidity pool
     * @param sender The sender passed to the operation. It can influence results (e.g., with user-dependent hooks)
     * @param params Parameters for the add liquidity and swap operation
     * @return amountsIn Array of amounts in for each token added to the pool, sorted in token registration order.
     */
    function queryAddUnbalancedLiquidityViaSwapExactIn(
        address pool,
        address sender,
        AddLiquidityAndSwapParams calldata params
    ) external returns (uint256[] memory amountsIn);

    /**
     * @notice Queries an `addUnbalancedLiquidityViaSwapExactOut` operation without actually executing it.
     * @param pool Address of the liquidity pool
     * @param sender The sender passed to the operation. It can influence results (e.g., with user-dependent hooks)
     * @param params Parameters for the add liquidity and swap operation
     * @return amountsIn Array of amounts in for each token added to the pool, sorted in token registration order.
     */
    function queryAddUnbalancedLiquidityViaSwapExactOut(
        address pool,
        address sender,
        AddLiquidityAndSwapParams calldata params
    ) external returns (uint256[] memory amountsIn);
}
