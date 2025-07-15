// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./VaultTypes.sol";

/**
 * @notice Data for the pool initialization hook.
 * @param sender Account originating the pool initialization operation
 * @param pool Address of the liquidity pool
 * @param tokens Pool tokens, in token registration order
 * @param exactAmountsIn Exact amounts of tokens to be added, sorted in token registration order
 * @param minBptAmountOut Minimum amount of pool tokens to be received
 * @param wethIsEth If true, incoming ETH will be wrapped to WETH and outgoing WETH will be unwrapped to ETH
 * @param userData Additional (optional) data sent with the request to add initial liquidity
 */
struct InitializeHookParams {
    address sender;
    address pool;
    IERC20[] tokens;
    uint256[] exactAmountsIn;
    uint256 minBptAmountOut;
    bool wethIsEth;
    bytes userData;
}

/**
 * @notice Data for the swap hook.
 * @param sender Account initiating the swap operation
 * @param kind Type of swap (exact in or exact out)
 * @param pool Address of the liquidity pool
 * @param tokenIn Token to be swapped from
 * @param tokenOut Token to be swapped to
 * @param amountGiven Amount given based on kind of the swap (e.g., tokenIn for exact in)
 * @param limit Maximum or minimum amount based on the kind of swap (e.g., maxAmountIn for exact out)
 * @param deadline Deadline for the swap, after which it will revert
 * @param wethIsEth If true, incoming ETH will be wrapped to WETH and outgoing WETH will be unwrapped to ETH
 * @param userData Additional (optional) data sent with the swap request
 */
struct SwapSingleTokenHookParams {
    address sender;
    SwapKind kind;
    address pool;
    IERC20 tokenIn;
    IERC20 tokenOut;
    uint256 amountGiven;
    uint256 limit;
    uint256 deadline;
    bool wethIsEth;
    bytes userData;
}

/**
 * @notice Data for the add liquidity hook.
 * @param sender Account originating the add liquidity operation
 * @param pool Address of the liquidity pool
 * @param maxAmountsIn Maximum amounts of tokens to be added, sorted in token registration order
 * @param minBptAmountOut Minimum amount of pool tokens to be received
 * @param kind Type of join (e.g., single or multi-token)
 * @param wethIsEth If true, incoming ETH will be wrapped to WETH and outgoing WETH will be unwrapped to ETH
 * @param userData Additional (optional) data sent with the request to add liquidity
 */
struct AddLiquidityHookParams {
    address sender;
    address pool;
    uint256[] maxAmountsIn;
    uint256 minBptAmountOut;
    AddLiquidityKind kind;
    bool wethIsEth;
    bytes userData;
}

/**
 * @notice Data for the remove liquidity hook.
 * @param sender Account originating the remove liquidity operation
 * @param pool Address of the liquidity pool
 * @param minAmountsOut Minimum amounts of tokens to be received, sorted in token registration order
 * @param maxBptAmountIn Maximum amount of pool tokens provided
 * @param kind Type of exit (e.g., single or multi-token)
 * @param wethIsEth If true, incoming ETH will be wrapped to WETH and outgoing WETH will be unwrapped to ETH
 * @param userData Additional (optional) data sent with the request to remove liquidity
 */
struct RemoveLiquidityHookParams {
    address sender;
    address pool;
    uint256[] minAmountsOut;
    uint256 maxBptAmountIn;
    RemoveLiquidityKind kind;
    bool wethIsEth;
    bytes userData;
}
