// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { SwapPathExactAmountIn } from "@balancer-labs/v3-interfaces/contracts/vault/BatchRouterTypes.sol";
import { BatchRouterE2ETest } from "./BatchRouterE2E.t.sol";

contract AggregatorBatchRouterE2ETest is BatchRouterE2ETest {
    using SafeERC20 for IERC20;

    function swapExactIn(
        SwapPathExactAmountIn[] memory pathsExactIn,
        bool wethIsEth,
        uint256 ethAmount
    )
        internal
        override
        returns (uint256[] memory calculatedPathAmountsOut, address[] memory tokensOut, uint256[] memory amountsOut)
    {
        vm.startPrank(alice);
        _prepay(pathsExactIn, wethIsEth);

        (calculatedPathAmountsOut, tokensOut, amountsOut) = aggregatorBatchRouter.swapExactIn{ value: ethAmount }(
            pathsExactIn,
            MAX_UINT256,
            wethIsEth,
            bytes("")
        );
        vm.stopPrank();
    }

    function _prepay(SwapPathExactAmountIn[] memory pathsExactIn, bool wethIsEth) internal {
        for (uint256 i = 0; i < pathsExactIn.length; i++) {
            IERC20 token = pathsExactIn[i].tokenIn;
            if (wethIsEth && token == weth) {
                continue;
            }

            pathsExactIn[i].tokenIn.safeTransfer(address(vault), pathsExactIn[i].exactAmountIn);
        }
    }

    function expectRevertSwapExactIn(
        SwapPathExactAmountIn[] memory pathsExactIn,
        uint256 deadline,
        bool wethIsEth,
        uint256 ethAmount,
        bytes memory error
    ) internal override {
        vm.startPrank(alice);
        _prepay(pathsExactIn, wethIsEth);

        vm.expectRevert(error);
        aggregatorBatchRouter.swapExactIn{ value: ethAmount }(pathsExactIn, deadline, wethIsEth, bytes(""));

        vm.stopPrank();
    }

    /***************************************************************************
                                    Add Liquidity Exact In
    ***************************************************************************/

    function testJoinSwapExactInSinglePathAndInitialAddLiquidityStep__Fuzz(bool wethIsEth) public override {
        // Skip this test using override
    }

    function testJoinSwapExactInSinglePathAndIntermediateAddLiquidityStep__Fuzz(bool wethIsEth) public override {
        // Skip this test using override
    }

    function testJoinSwapExactInMultiPathAndInitialFinalAddLiquidityStep__Fuzz(bool wethIsEth) public override {
        // Skip this test using override
    }

    /***************************************************************************
                                    Remove Liquidity Exact In
    ***************************************************************************/

    function testExitSwapExactInSinglePathAndInitialRemoveLiquidityStep__Fuzz(bool wethIsEth) public override {
        // Skip this test using override
    }

    function testExitSwapExactInSinglePathAndIntermediateRemoveLiquidityStep__Fuzz(bool wethIsEth) public override {
        // Skip this test using override
    }

    function testExitSwapExactInSinglePathAndFinalRemoveLiquidityStep__Fuzz(bool wethIsEth) public override {
        // Skip this test using override
    }

    function testExitSwapExactInMultiPathAndFinalRemoveLiquidityStep__Fuzz(bool wethIsEth) public override {
        // Skip this test using override
    }

    function testExitSwapExactInMultiPathAndIntermediateRemoveLiquidityStep__Fuzz(bool wethIsEth) public override {
        // Skip this test using override
    }
}
