// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./RouterTypes.sol";

/// @notice Router interface for adding unbalanced liquidity via a combination of a proportional add and a swap.
interface IAddUnbalancedLiquidityViaSwapRouter {
    struct AddLiquidityAndSwapParams {
        uint256 minBptAmountOut;
        IERC20 exactToken;
        uint256 exactAmount;
        uint256 maxAdjustableAmount;
        bytes addLiquidityUserData;
        bytes swapUserData;
    }

    struct AddLiquidityAndSwapHookParams {
        address pool;
        address sender;
        uint256 deadline;
        bool wethIsEth;
        AddLiquidityAndSwapParams operationParams;
    }

    /**
     * @notice Adds liquidity to a pool with proportional token amounts and swap in the same transaction.
     * @param pool Address of the liquidity pool
     * @param deadline Timestamp after which the transaction will revert
     * @param wethIsEth If true, incoming ETH will be wrapped to WETH and outgoing WETH will be unwrapped to ETH
     * @param params Parameters for the add liquidity and swap operation
     * @return amountsIn Array of amounts in for each token added to the pool, sorted in token registration order.
     */
    function addUnbalancedLiquidityViaSwap(
        address pool,
        uint256 deadline,
        bool wethIsEth,
        AddLiquidityAndSwapParams calldata params
    ) external payable returns (uint256[] memory amountsIn);

    /**
     * @notice Queries an `addUnbalancedLiquidityViaSwap` operation without actually executing it.
     * @param pool Address of the liquidity pool
     * @param sender The sender passed to the operation. It can influence results (e.g., with user-dependent hooks)
     * @param params Parameters for the add liquidity and swap operation
     * @return amountsIn Array of amounts in for each token added to the pool, sorted in token registration order.
     */
    function queryAddUnbalancedLiquidityViaSwap(
        address pool,
        address sender,
        AddLiquidityAndSwapParams calldata params
    ) external returns (uint256[] memory amountsIn);
}
