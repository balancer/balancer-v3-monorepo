// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./RouterTypes.sol";

/// @notice Router interface for adding unbalanced liquidity via a combination of a proportional add and a swap.
interface IAddUnbalancedLiquidityViaSwapRouter {
    struct AddLiquidityAndSwapParams {
        uint256[] proportionalMaxAmountsIn;
        uint256 exactProportionalBptAmountOut;
        IERC20 tokenExactIn;
        IERC20 tokenMaxIn;
        uint256 exactAmountIn;
        uint256 maxAmountIn;
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

    function addUnbalancedLiquidityViaSwap(
        address pool,
        uint256 deadline,
        bool wethIsEth,
        AddLiquidityAndSwapParams calldata params
    ) external payable returns (uint256[] memory amountsIn);

    function queryAddUnbalancedLiquidityViaSwap(
        address pool,
        address sender,
        AddLiquidityAndSwapParams calldata params
    ) external returns (uint256[] memory amountsIn);
}
