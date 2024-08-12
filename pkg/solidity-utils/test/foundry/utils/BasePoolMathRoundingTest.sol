// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import "../../../contracts/math/FixedPoint.sol";
import "../../../contracts/test/BasePoolMathMock.sol";

abstract contract BasePoolMathRoundingTest is Test {
    uint256 constant MIN_BALANCE = 1e18;
    uint256 constant MIN_AMOUNT = 1e12;
    uint256 constant MAX_AMOUNT = 1000e18;

    uint256 constant MIN_SWAP_FEE = 0;
    // Max swap fee of 50%. In practice this is way too high for a static fee anyways.
    uint256 constant MAX_SWAP_FEE = 50e16;

    uint256 delta = 1e3;

    BasePoolMathMock mock;

    function setUp() public virtual {
        mock = createMathMock();
    }

    function createMathMock() internal virtual returns (BasePoolMathMock);

    function testComputeProportionalAmountsIn__Fuzz(
        uint256[2] calldata rawBalances,
        uint256 rawBptAmountOut
    ) external view {
        uint256[] memory balances = new uint256[](rawBalances.length);
        for (uint256 i = 0; i < balances.length; ++i) {
            balances[i] = bound(rawBalances[i], MIN_BALANCE, MAX_AMOUNT);
        }
        uint256 totalSupply = mock.computeInvariant(balances);
        uint256 bptAmountOut = bound(rawBptAmountOut, MIN_AMOUNT, totalSupply);

        uint256[] memory standardResult = mock.computeProportionalAmountsIn(balances, totalSupply, bptAmountOut);

        uint256 roundedUpBptAmountOut = bptAmountOut + 1;
        uint256 roundedDownBptAmountOut = bptAmountOut - 1;

        uint256[] memory roundedUpResult = mock.computeProportionalAmountsIn(
            balances,
            totalSupply,
            roundedUpBptAmountOut
        );
        uint256[] memory roundedDownResult = mock.computeProportionalAmountsIn(
            balances,
            totalSupply,
            roundedDownBptAmountOut
        );

        for (uint256 i = 0; i < balances.length; ++i) {
            assertGe(
                roundedUpResult[i],
                standardResult[i],
                "roundedUpResult < standardResult (computeProportionalAmountsIn)"
            );
            assertLe(
                roundedDownResult[i],
                standardResult[i],
                "roundedDownResult > standardResult (computeProportionalAmountsIn)"
            );
        }
    }

    function testComputeProportionalAmountsOut__Fuzz(
        uint256[2] calldata rawBalances,
        uint256 rawBptAmountIn
    ) external view {
        uint256[] memory balances = new uint256[](rawBalances.length);
        for (uint256 i = 0; i < balances.length; ++i) {
            balances[i] = bound(rawBalances[i], MIN_BALANCE, MAX_AMOUNT);
        }
        uint256 totalSupply = mock.computeInvariant(balances);
        uint256 bptAmountIn = bound(rawBptAmountIn, MIN_AMOUNT, totalSupply);

        uint256[] memory standardResult = mock.computeProportionalAmountsOut(balances, totalSupply, bptAmountIn);

        uint256 roundedUpBptAmountIn = bptAmountIn + 1;
        uint256 roundedDownBptAmountIn = bptAmountIn - 1;

        uint256[] memory roundedUpResult = mock.computeProportionalAmountsOut(
            balances,
            totalSupply,
            roundedUpBptAmountIn
        );
        uint256[] memory roundedDownResult = mock.computeProportionalAmountsOut(
            balances,
            totalSupply,
            roundedDownBptAmountIn
        );

        for (uint256 i = 0; i < balances.length; ++i) {
            assertGe(
                roundedUpResult[i],
                standardResult[i],
                "roundedUpResult < standardResult (computeProportionalAmountsOut)"
            );
            assertLe(
                roundedDownResult[i],
                standardResult[i],
                "roundedDownResult > standardResult (computeProportionalAmountsOut)"
            );
        }
    }

    function testComputeAddLiquidityUnbalanced__Fuzz(
        uint256[2] calldata rawBalances,
        uint256[2] calldata rawAmountsIn,
        uint64 rawSwapFee
    ) external view {
        uint256[] memory balances = new uint256[](rawBalances.length);
        uint256[] memory amountsIn = new uint256[](2);
        for (uint256 i = 0; i < balances.length; ++i) {
            balances[i] = bound(rawBalances[i], MIN_BALANCE, MAX_AMOUNT);
            amountsIn[i] = bound(rawAmountsIn[i], MIN_BALANCE, MAX_AMOUNT);
        }
        uint256 totalSupply = mock.computeInvariant(balances);
        uint256 swapFee = bound(rawSwapFee, MIN_SWAP_FEE, MAX_SWAP_FEE);

        uint256 standardResultBpt;
        uint256[] memory standardResultFees;

        (standardResultBpt, standardResultFees) = mock.computeAddLiquidityUnbalanced(
            balances,
            amountsIn,
            totalSupply,
            swapFee
        );

        uint256[] memory roundedUpAmountsIn = new uint256[](balances.length);
        uint256[] memory roundedDownAmountsIn = new uint256[](balances.length);

        for (uint256 i = 0; i < balances.length; ++i) {
            roundedUpAmountsIn[i] = amountsIn[i] + 1;
            roundedDownAmountsIn[i] = amountsIn[i] - 1;
        }

        uint256 roundedUpBpt;
        uint256[] memory roundedUpFees;
        (roundedUpBpt, roundedUpFees) = mock.computeAddLiquidityUnbalanced(
            balances,
            roundedUpAmountsIn,
            totalSupply,
            swapFee
        );

        uint256 roundedDownBpt;
        uint256[] memory roundedDownFees;
        (roundedDownBpt, roundedDownFees) = mock.computeAddLiquidityUnbalanced(
            balances,
            roundedDownAmountsIn,
            totalSupply,
            swapFee
        );

        assertGe(roundedUpBpt, standardResultBpt, "roundedUpBpt < standardResultBpt (computeAddLiquidityUnbalanced)");
        assertLe(
            roundedDownBpt,
            standardResultBpt,
            "roundedDownBpt > standardResultBpt (computeAddLiquidityUnbalanced)"
        );

        for (uint256 i = 0; i < balances.length; ++i) {
            assertGe(
                roundedUpFees[i] + delta,
                standardResultFees[i],
                "roundedUpFees + delta > standardResultFees (computeAddLiquidityUnbalanced)"
            );
            assertLe(
                roundedDownFees[i],
                standardResultFees[i] + delta,
                "roundedDownFees < standardResultFees + delta (computeAddLiquidityUnbalanced)"
            );
        }
    }

    function testComputeAddLiquiditySingleTokenExactOut__Fuzz(
        uint256 rawBalance,
        uint256 rawTokenInIndex,
        uint256 rawBptAmountOut,
        uint64 rawSwapFee
    ) external view {
        uint256[] memory balances = new uint256[](2);
        uint256 balance = bound(rawBalance, MIN_BALANCE * 4, MAX_AMOUNT);
        for (uint256 i = 0; i < balances.length; ++i) {
            balances[i] = balance;
        }

        uint256 tokenInIndex = bound(rawTokenInIndex, 0, 1);
        uint256 bptAmountOut = bound(rawBptAmountOut, MIN_AMOUNT, MAX_AMOUNT);
        uint256 totalSupply = mock.computeInvariant(balances);
        uint256 swapFee = bound(rawSwapFee, MIN_SWAP_FEE, MAX_SWAP_FEE);

        uint256 standardResultAmountInWithFee;
        uint256[] memory standardResultFees;

        (standardResultAmountInWithFee, standardResultFees) = mock.computeAddLiquiditySingleTokenExactOut(
            balances,
            tokenInIndex,
            bptAmountOut,
            totalSupply,
            swapFee
        );

        uint256 roundedUpBptAmountOut = bptAmountOut + 1;
        uint256 roundedDownBptAmountOut = bptAmountOut - 1;

        uint256 roundedUpAmountInWithFee;
        uint256[] memory roundedUpFees;
        (roundedUpAmountInWithFee, roundedUpFees) = mock.computeAddLiquiditySingleTokenExactOut(
            balances,
            tokenInIndex,
            roundedUpBptAmountOut,
            totalSupply,
            swapFee
        );

        uint256 roundedDownAmountInWithFee;
        uint256[] memory roundedDownFees;
        (roundedDownAmountInWithFee, roundedDownFees) = mock.computeAddLiquiditySingleTokenExactOut(
            balances,
            tokenInIndex,
            roundedDownBptAmountOut,
            totalSupply,
            swapFee
        );

        assertGe(
            roundedUpAmountInWithFee + delta,
            standardResultAmountInWithFee,
            "roundedUpAmountInWithFee + delta < standardResultAmountInWithFee (computeAddLiquiditySingleTokenExactOut)"
        );
        assertLe(
            roundedDownAmountInWithFee,
            standardResultAmountInWithFee + delta,
            "roundedDownAmountInWithFee > standardResultAmountInWithFee + delta (computeAddLiquiditySingleTokenExactOut)"
        );

        for (uint256 i = 0; i < balances.length; ++i) {
            assertGe(
                roundedUpFees[i] + delta,
                standardResultFees[i],
                "roundedUpFees + delta > standardResultFees (computeAddLiquiditySingleTokenExactOut)"
            );
            assertLe(
                roundedDownFees[i],
                standardResultFees[i] + delta,
                "roundedDownFees < standardResultFees + delta (computeAddLiquiditySingleTokenExactOut)"
            );
        }
    }

    function testComputeRemoveLiquiditySingleTokenExactOut__Fuzz(
        uint256 rawBalance,
        uint256 rawTokenOutIndex,
        uint256 rawAmountOut,
        uint64 rawSwapFee
    ) external view {
        uint256[] memory balances = new uint256[](2);
        uint256 balance = bound(rawBalance, MIN_BALANCE * 5, MAX_AMOUNT);

        for (uint256 i = 0; i < balances.length; ++i) {
            balances[i] = balance;
        }
        uint256 tokenOutIndex = bound(rawTokenOutIndex, 0, 1);
        uint256 amountOut = bound(rawAmountOut, MIN_BALANCE, balances[tokenOutIndex] / 5);

        uint256 totalSupply = mock.computeInvariant(balances);
        uint256 swapFee = bound(rawSwapFee, MIN_SWAP_FEE, MAX_SWAP_FEE);

        uint256 standardResultBptAmountIn;
        uint256[] memory standardResultFees;

        (standardResultBptAmountIn, standardResultFees) = mock.computeRemoveLiquiditySingleTokenExactOut(
            balances,
            tokenOutIndex,
            amountOut,
            totalSupply,
            swapFee
        );

        uint256 roundedUpAmountOut = amountOut + 1;
        uint256 roundedDownAmountOut = amountOut - 1;

        uint256 roundedUpBptAmountIn;
        uint256[] memory roundedUpFees;
        (roundedUpBptAmountIn, roundedUpFees) = mock.computeRemoveLiquiditySingleTokenExactOut(
            balances,
            tokenOutIndex,
            roundedUpAmountOut,
            totalSupply,
            swapFee
        );

        uint256 roundedDownBptAmountIn;
        uint256[] memory roundedDownFees;
        (roundedDownBptAmountIn, roundedDownFees) = mock.computeRemoveLiquiditySingleTokenExactOut(
            balances,
            tokenOutIndex,
            roundedDownAmountOut,
            totalSupply,
            swapFee
        );

        assertGe(
            roundedUpBptAmountIn + delta,
            standardResultBptAmountIn,
            "roundedUpBptAmountIn + delta < standardResultBptAmountIn (computeRemoveLiquiditySingleTokenExactOut)"
        );
        assertLe(
            roundedDownBptAmountIn,
            standardResultBptAmountIn + delta,
            "roundedDownBptAmountIn > standardResultBptAmountIn + delta (computeRemoveLiquiditySingleTokenExactOut)"
        );

        for (uint256 i = 0; i < balances.length; ++i) {
            assertGe(
                roundedUpFees[i] + delta,
                standardResultFees[i],
                "roundedUpFees + delta > standardResultFees (computeRemoveLiquiditySingleTokenExactOut)"
            );
            assertLe(
                roundedDownFees[i],
                standardResultFees[i] + delta,
                "roundedDownFees < standardResultFees + delta (computeRemoveLiquiditySingleTokenExactOut)"
            );
        }
    }

    function testComputeRemoveLiquiditySingleTokenExactIn__Fuzz(
        uint256 rawBalance,
        uint256 rawTokenOutIndex,
        uint256 rawBptAmountIn,
        uint64 rawSwapFee
    ) external view {
        uint256[] memory balances = new uint256[](2);

        uint balance = bound(rawBalance, MIN_BALANCE, MAX_AMOUNT);
        for (uint256 i = 0; i < balances.length; ++i) {
            balances[i] = balance;
        }

        uint256 tokenOutIndex = bound(rawTokenOutIndex, 0, 1);
        uint256 totalSupply = mock.computeInvariant(balances);
        uint256 bptAmountIn = bound(rawBptAmountIn, MIN_AMOUNT, totalSupply / 4);
        uint256 swapFee = bound(rawSwapFee, MIN_SWAP_FEE, MAX_SWAP_FEE);

        uint256 standardResultAmountOutWithFee;
        uint256[] memory standardResultFees;

        (standardResultAmountOutWithFee, standardResultFees) = mock.computeRemoveLiquiditySingleTokenExactIn(
            balances,
            tokenOutIndex,
            bptAmountIn,
            totalSupply,
            swapFee
        );

        uint256 roundedUpBptAmountIn = bptAmountIn + 1;
        uint256 roundedDownBptAmountIn = bptAmountIn - 1;

        uint256 roundedUpAmountOutWithFee;
        uint256[] memory roundedUpFees;
        (roundedUpAmountOutWithFee, roundedUpFees) = mock.computeRemoveLiquiditySingleTokenExactIn(
            balances,
            tokenOutIndex,
            roundedUpBptAmountIn,
            totalSupply,
            swapFee
        );

        uint256 roundedDownAmountOutWithFee;
        uint256[] memory roundedDownFees;
        (roundedDownAmountOutWithFee, roundedDownFees) = mock.computeRemoveLiquiditySingleTokenExactIn(
            balances,
            tokenOutIndex,
            roundedDownBptAmountIn,
            totalSupply,
            swapFee
        );

        assertGe(
            roundedUpAmountOutWithFee,
            standardResultAmountOutWithFee,
            "roundedUpAmountOutWithFee < standardResultAmountOutWithFee (computeRemoveLiquiditySingleTokenExactIn)"
        );
        assertLe(
            roundedDownAmountOutWithFee,
            standardResultAmountOutWithFee,
            "roundedDownAmountOutWithFee > standardResultAmountOutWithFee (computeRemoveLiquiditySingleTokenExactIn)"
        );

        for (uint256 i = 0; i < balances.length; ++i) {
            assertGe(
                roundedUpFees[i] + delta,
                standardResultFees[i],
                "roundedUpFees + delta > standardResultFees (computeRemoveLiquiditySingleTokenExactIn)"
            );
            assertLe(
                roundedDownFees[i],
                standardResultFees[i] + delta,
                "roundedDownFees < standardResultFees + delta (computeRemoveLiquiditySingleTokenExactIn)"
            );
        }
    }
}
