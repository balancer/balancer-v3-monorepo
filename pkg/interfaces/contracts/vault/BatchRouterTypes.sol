// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

struct SwapPathStep {
    address pool;
    IERC20 tokenOut;
    // If true, the "pool" is an ERC4626 Buffer. Used to wrap/unwrap tokens if pool doesn't have enough liquidity.
    bool isBuffer;
}

struct SwapPathExactAmountIn {
    IERC20 tokenIn;
    // For each step:
    // If tokenIn == pool, use removeLiquidity SINGLE_TOKEN_EXACT_IN.
    // If tokenOut == pool, use addLiquidity UNBALANCED.
    SwapPathStep[] steps;
    uint256 exactAmountIn;
    uint256 minAmountOut;
}

struct SwapPathExactAmountOut {
    IERC20 tokenIn;
    // for each step:
    // If tokenIn == pool, use removeLiquidity SINGLE_TOKEN_EXACT_OUT.
    // If tokenOut == pool, use addLiquidity SINGLE_TOKEN_EXACT_OUT.
    SwapPathStep[] steps;
    uint256 maxAmountIn;
    uint256 exactAmountOut;
}

struct SwapExactInHookParams {
    address sender;
    SwapPathExactAmountIn[] paths;
    uint256 deadline;
    bool wethIsEth;
    bytes userData;
}

struct SwapExactOutHookParams {
    address sender;
    SwapPathExactAmountOut[] paths;
    uint256 deadline;
    bool wethIsEth;
    bytes userData;
}
