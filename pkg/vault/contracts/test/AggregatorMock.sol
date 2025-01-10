// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IRouterSwap } from "@balancer-labs/v3-interfaces/contracts/vault/IRouterSwap.sol";
import { IRouterPaymentHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IRouterPaymentHooks.sol";

contract AggregatorMock is IRouterPaymentHooks {
    address internal vault;
    IRouterSwap internal router;
    bool public isPaymentHookActive;

    constructor(address vault_, IRouterSwap router_) {
        vault = vault_;
        router = router_;
        isPaymentHookActive = true;
    }

    function onPay(IERC20 token, uint256 amount, bytes calldata) external {
        if (!isPaymentHookActive) {
            return;
        }

        token.transfer(address(vault), amount);
    }

    function setPaymentHookActive(bool active) external {
        isPaymentHookActive = active;
    }

    function swapSingleTokenExactIn(
        address pool,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 exactAmountIn,
        uint256 minAmountOut,
        uint256 deadline,
        bool wethIsEth,
        bytes calldata userData
    ) external returns (uint256 amountOut) {
        return
            router.swapSingleTokenExactIn(
                pool,
                tokenIn,
                tokenOut,
                exactAmountIn,
                minAmountOut,
                deadline,
                wethIsEth,
                userData
            );
    }

    function swapSingleTokenExactOut(
        address pool,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 exactAmountOut,
        uint256 maxAmountIn,
        uint256 deadline,
        bool wethIsEth,
        bytes calldata userData
    ) external returns (uint256) {
        return
            router.swapSingleTokenExactOut(
                pool,
                tokenIn,
                tokenOut,
                exactAmountOut,
                maxAmountIn,
                deadline,
                wethIsEth,
                userData
            );
    }
}
