// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {
    SwapPathExactAmountIn,
    SwapPathExactAmountOut
} from "@balancer-labs/v3-interfaces/contracts/vault/BatchRouterTypes.sol";
import { SwapKind } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { BatchRouterE2ETest } from "./BatchRouterE2E.t.sol";

contract AggregatorBatchRouterE2ETest is BatchRouterE2ETest {
    using SafeERC20 for IERC20;

    /***************************************************************************
                                Exact In
    ***************************************************************************/

    function querySwapExactIn(
        SwapPathExactAmountIn[] memory pathsExactIn
    )
        internal
        override
        returns (uint256[] memory pathAmountsOut, address[] memory tokensOut, uint256[] memory amountsOut)
    {
        uint256 snapshot = vm.snapshotState();

        _prankStaticCall();
        (pathAmountsOut, tokensOut, amountsOut) = aggregatorBatchRouter.querySwapExactIn(
            pathsExactIn,
            address(0),
            bytes("")
        );

        vm.revertToState(snapshot);
    }

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
                                Exact Out
    ***************************************************************************/

    function querySwapExactOut(
        SwapPathExactAmountOut[] memory pathsExactOut
    )
        internal
        override
        returns (uint256[] memory pathAmountsIn, address[] memory tokensIn, uint256[] memory amountsIn)
    {
        uint256 snapshot = vm.snapshotState();

        _prankStaticCall();
        (pathAmountsIn, tokensIn, amountsIn) = aggregatorBatchRouter.querySwapExactOut(
            pathsExactOut,
            address(0),
            bytes("")
        );

        vm.revertToState(snapshot);
    }

    function swapExactOut(
        SwapPathExactAmountOut[] memory pathsExactOut,
        bool wethIsEth,
        uint256 ethAmount
    )
        internal
        override
        returns (uint256[] memory pathAmountsIn, address[] memory tokensIn, uint256[] memory amountsIn)
    {
        vm.startPrank(alice);
        _prepay(pathsExactOut, wethIsEth);

        (pathAmountsIn, tokensIn, amountsIn) = aggregatorBatchRouter.swapExactOut{ value: ethAmount }(
            pathsExactOut,
            MAX_UINT256,
            wethIsEth,
            bytes("")
        );
        vm.stopPrank();
    }

    function expectRevertSwapExactOut(
        SwapPathExactAmountOut[] memory pathsExactOut,
        uint256 deadline,
        bool wethIsEth,
        uint256 ethAmount,
        bytes memory error
    ) internal override {
        vm.startPrank(alice);
        _prepay(pathsExactOut, wethIsEth);

        vm.expectRevert(error);
        aggregatorBatchRouter.swapExactOut{ value: ethAmount }(pathsExactOut, deadline, wethIsEth, bytes(""));
        vm.stopPrank();
    }

    /***************************************************************************
                                Other functions
    ***************************************************************************/

    function _prepay(SwapPathExactAmountIn[] memory pathsExactIn, bool wethIsEth) internal {
        for (uint256 i = 0; i < pathsExactIn.length; i++) {
            IERC20 token = pathsExactIn[i].tokenIn;
            if (wethIsEth && token == weth) {
                continue;
            }

            pathsExactIn[i].tokenIn.safeTransfer(address(vault), pathsExactIn[i].exactAmountIn);
        }
    }

    function _prepay(SwapPathExactAmountOut[] memory pathsExactOut, bool wethIsEth) internal {
        for (uint256 i = 0; i < pathsExactOut.length; i++) {
            IERC20 token = pathsExactOut[i].tokenIn;
            if (wethIsEth && token == weth) {
                continue;
            }

            pathsExactOut[i].tokenIn.safeTransfer(address(vault), pathsExactOut[i].maxAmountIn);
        }
    }

    /***************************************************************************
                                    Add Liquidity
    ***************************************************************************/

    function _testJoinSwapSinglePathAndInitialAddLiquidityStep(SwapKind, bool) internal override {
        // Add/Remove liquidity operations are unsupported by the aggregate router.
        vm.skip(true);
    }

    function _testJoinSwapSinglePathAndIntermediateAddLiquidityStep(SwapKind, bool) internal override {
        // Add/Remove liquidity operations are unsupported by the aggregate router.
        vm.skip(true);
    }

    function _testJoinSwapMultiPathAndInitialFinalAddLiquidityStep(SwapKind, bool) internal override {
        // Add/Remove liquidity operations are unsupported by the aggregate router.
        vm.skip(true);
    }

    /***************************************************************************
                                    Remove Liquidity
    ***************************************************************************/

    function _testExitSwapSinglePathAndInitialRemoveLiquidityStep(SwapKind, bool) internal override {
        // Add/Remove liquidity operations are unsupported by the aggregate router.
        vm.skip(true);
    }

    function _testExitSwapSinglePathAndIntermediateRemoveLiquidityStep(
        SwapKind,
        bool
    ) internal override {
        // Add/Remove liquidity operations are unsupported by the aggregate router.
        vm.skip(true);
    }

    function _testExitSwapSinglePathAndFinalRemoveLiquidityStep(SwapKind, bool) internal override {
        // Add/Remove liquidity operations are unsupported by the aggregate router.
        vm.skip(true);
    }

    function _testExitSwapMultiPathAndFinalRemoveLiquidityStep(SwapKind, bool) internal override {
        // Add/Remove liquidity operations are unsupported by the aggregate router.
        vm.skip(true);
    }

    function _testExitSwapMultiPathAndIntermediateRemoveLiquidityStep(SwapKind, bool) internal override {
        // Add/Remove liquidity operations are unsupported by the aggregate router.
        vm.skip(true);
    }
}
