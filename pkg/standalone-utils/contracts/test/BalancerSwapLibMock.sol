// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { BalancerSwapLib, BalancerContext } from "../BalancerSwapLib.sol";

contract BalancerSwapLibMock {
    using BalancerSwapLib for *;

    BalancerContext public context;

    constructor(address aggregatorRouter, address aggregatorBatchRouter) {
        context = BalancerSwapLib.createContext(aggregatorRouter, aggregatorBatchRouter);
    }

    function swapExactIn(
        address pool,
        IERC20 poolTokenIn,
        IERC20 poolTokenOut,
        uint256 exactAmountIn,
        uint256 minAmountOut,
        uint256 deadline,
        bytes calldata userData
    ) external returns (uint256 amountOut) {
        return
            context
                .buildSwapExactIn(pool, poolTokenIn, poolTokenOut, exactAmountIn, minAmountOut, deadline)
                .withUserData(userData)
                .execute();
    }

    function swapExactOut(
        address pool,
        IERC20 poolTokenIn,
        IERC20 poolTokenOut,
        uint256 exactAmountOut,
        uint256 maxAmountIn,
        uint256 deadline,
        bytes calldata userData
    ) external returns (uint256 amountIn) {
        return
            context
                .buildSwapExactOut(pool, poolTokenIn, poolTokenOut, exactAmountOut, maxAmountIn, deadline)
                .withUserData(userData)
                .execute();
    }
}
