// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../../contracts/math/FixedPoint.sol";
import "../../contracts/test/BasePoolMathMock.sol";

contract BasePoolMathRoundingTest is Test {
    uint256 constant MIN_BALANCE = 1e18;
    uint256 constant MIN_AMOUNT = 1e12;
    uint256 constant MAX_AMOUNT = 1000e18;
    uint256 constant FP_ONE = 1e18;

    uint256 constant MAX_IN_RATIO = 0.3e18;
    uint256 constant MAX_OUT_RATIO = 0.3e18;

    uint256 constant MIN_SWAP_FEE = 0;
    uint256 constant MAX_SWAP_FEE = 0.8e18;
    uint256 constant DELTA = 1e12;

    BasePoolMathMock mock;

    function setUp() public {
        mock = new BasePoolMathMock();
    }

    function testComputeProportionalAmountsIn__Fuzz(
        uint256 rawTotalSupply,
        uint256[2] calldata rawBalances,
        uint256 rawBptAmountOut,
        bool flipBit
    ) external view {
        uint256[] memory balances = new uint256[](2);
        for (uint256 i = 0; i < balances.length; ++i) {
            balances[i] = bound(rawBalances[i], MIN_BALANCE, MAX_AMOUNT);
        }
        uint256 totalSupply = bound(rawTotalSupply, MIN_BALANCE, MAX_AMOUNT);
        uint256 bptAmountOut = bound(rawBptAmountOut, MIN_AMOUNT, totalSupply);

        uint256[] memory standardResult = mock.computeProportionalAmountsIn(balances, totalSupply, bptAmountOut);

        uint256 roundedUpBptAmountOut = flipBit ? bptAmountOut + 1 : bptAmountOut;
        uint256 roundedDownBptAmountOut = flipBit ? bptAmountOut - 1 : bptAmountOut;

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
            if (flipBit) {
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
            } else {
                assertEq(
                    roundedUpResult[i],
                    standardResult[i],
                    "roundedUpResult != standardResult (computeProportionalAmountsIn)"
                );
                assertEq(
                    roundedDownResult[i],
                    standardResult[i],
                    "roundedDownResult != standardResult (computeProportionalAmountsIn)"
                );
            }
        }
    }

    function testComputeProportionalAmountsOut__Fuzz(
        uint256 rawTotalSupply,
        uint256[2] calldata rawBalances,
        uint256 rawBptAmountIn,
        bool flipBit
    ) external view {
        uint256[] memory balances = new uint256[](2);
        for (uint256 i = 0; i < balances.length; ++i) {
            balances[i] = bound(rawBalances[i], MIN_BALANCE, MAX_AMOUNT);
        }
        uint256 totalSupply = bound(rawTotalSupply, MIN_BALANCE, MAX_AMOUNT);
        uint256 bptAmountIn = bound(rawBptAmountIn, MIN_AMOUNT, totalSupply);

        uint256[] memory standardResult = mock.computeProportionalAmountsOut(balances, totalSupply, bptAmountIn);

        uint256 roundedUpBptAmountIn = flipBit ? bptAmountIn + 1 : bptAmountIn;
        uint256 roundedDownBptAmountIn = flipBit ? bptAmountIn - 1 : bptAmountIn;

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
            if (flipBit) {
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
            } else {
                assertEq(
                    roundedUpResult[i],
                    standardResult[i],
                    "roundedUpResult != standardResult (computeProportionalAmountsOut)"
                );
                assertEq(
                    roundedDownResult[i],
                    standardResult[i],
                    "roundedDownResult != standardResult (computeProportionalAmountsOut)"
                );
            }
        }
    }

    function testComputeAddLiquidityUnbalanced__Fuzz(
        uint256[2] calldata rawBalances,
        uint256[2] calldata rawAmountsIn,
        uint256 rawTotalSupply,
        uint64 rawSwapFee,
        bool flipBit
    ) external view {
        uint256[] memory balances = new uint256[](2);
        uint256[] memory amountsIn = new uint256[](2);
        for (uint256 i = 0; i < balances.length; ++i) {
            balances[i] = bound(rawBalances[i], MIN_BALANCE, MAX_AMOUNT);
            amountsIn[i] = bound(rawAmountsIn[i], MIN_BALANCE, MAX_AMOUNT);
        }
        uint256 totalSupply = bound(rawTotalSupply, MIN_BALANCE, MAX_AMOUNT);
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
            roundedUpAmountsIn[i] = flipBit ? amountsIn[i] + 1 : amountsIn[i];
            roundedDownAmountsIn[i] = flipBit ? amountsIn[i] - 1 : amountsIn[i];
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

        if (flipBit) {
            assertApproxEqAbs(
                roundedUpBpt,
                standardResultBpt,
                DELTA,
                "roundedUpBpt != standardResultBpt with DELTA (computeAddLiquidityUnbalanced)"
            );
            assertApproxEqAbs(
                roundedDownBpt,
                standardResultBpt,
                DELTA,
                "roundedDownBpt != standardResultBpt with DELTA (computeAddLiquidityUnbalanced)"
            );

            for (uint256 i = 0; i < balances.length; ++i) {
                assertApproxEqAbs(
                    roundedUpFees[i],
                    standardResultFees[i],
                    DELTA,
                    "roundedUpFees != standardResultFees with DELTA (computeAddLiquidityUnbalanced)"
                );
                assertApproxEqAbs(
                    roundedDownFees[i],
                    standardResultFees[i],
                    DELTA,
                    "roundedDownFees != standardResultFees with DELTA (computeAddLiquidityUnbalanced)"
                );
            }
        } else {
            assertEq(
                roundedUpBpt,
                standardResultBpt,
                "roundedUpBpt != standardResultBpt (computeAddLiquidityUnbalanced)"
            );
            assertEq(
                roundedDownBpt,
                standardResultBpt,
                "roundedDownBpt != standardResultBpt (computeAddLiquidityUnbalanced)"
            );
            for (uint256 i = 0; i < balances.length; ++i) {
                assertEq(
                    roundedUpFees[i],
                    standardResultFees[i],
                    "roundedUpFees != standardResultFees (computeAddLiquidityUnbalanced)"
                );
                assertEq(
                    roundedDownFees[i],
                    standardResultFees[i],
                    "roundedDownFees != standardResultFees (computeAddLiquidityUnbalanced)"
                );
            }
        }
    }

    function testComputeAddLiquiditySingleTokenExactOut__Fuzz(
        uint256[2] calldata rawBalances,
        uint256 rawTokenInIndex,
        uint256 rawBptAmountOut,
        uint256 rawTotalSupply,
        uint64 rawSwapFee,
        bool flipBit
    ) external view {
        uint256[] memory balances = new uint256[](2);
        for (uint256 i = 0; i < balances.length; ++i) {
            balances[i] = bound(rawBalances[i], MIN_BALANCE, MAX_AMOUNT);
        }
        uint256 tokenInIndex = bound(rawTokenInIndex, 0, 1);
        uint256 bptAmountOut = bound(rawBptAmountOut, MIN_AMOUNT, MAX_AMOUNT);
        uint256 totalSupply = bound(rawTotalSupply, MIN_BALANCE, MAX_AMOUNT);
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

        uint256 roundedUpBptAmountOut = flipBit ? bptAmountOut + 1 : bptAmountOut;
        uint256 roundedDownBptAmountOut = flipBit ? bptAmountOut - 1 : bptAmountOut;

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

        if (flipBit) {
            assertApproxEqAbs(
                roundedUpAmountInWithFee,
                standardResultAmountInWithFee,
                DELTA,
                "roundedUpAmountInWithFee != standardResultAmountInWithFee with DELTA (computeAddLiquiditySingleTokenExactOut)"
            );
            assertApproxEqAbs(
                roundedDownAmountInWithFee,
                standardResultAmountInWithFee,
                DELTA,
                "roundedDownAmountInWithFee != standardResultAmountInWithFee with DELTA (computeAddLiquiditySingleTokenExactOut)"
            );

            for (uint256 i = 0; i < balances.length; ++i) {
                assertApproxEqAbs(
                    roundedUpFees[i],
                    standardResultFees[i],
                    DELTA,
                    "roundedUpFees != standardResultFees with DELTA (computeAddLiquiditySingleTokenExactOut)"
                );
                assertApproxEqAbs(
                    roundedDownFees[i],
                    standardResultFees[i],
                    DELTA,
                    "roundedDownFees != standardResultFees with DELTA (computeAddLiquiditySingleTokenExactOut)"
                );
            }
        } else {
            assertEq(
                roundedUpAmountInWithFee,
                standardResultAmountInWithFee,
                "roundedUpAmountInWithFee != standardResultAmountInWithFee (computeAddLiquiditySingleTokenExactOut)"
            );
            assertEq(
                roundedDownAmountInWithFee,
                standardResultAmountInWithFee,
                "roundedDownAmountInWithFee != standardResultAmountInWithFee (computeAddLiquiditySingleTokenExactOut)"
            );
            for (uint256 i = 0; i < balances.length; ++i) {
                assertEq(
                    roundedUpFees[i],
                    standardResultFees[i],
                    "roundedUpFees != standardResultFees (computeAddLiquiditySingleTokenExactOut)"
                );
                assertEq(
                    roundedDownFees[i],
                    standardResultFees[i],
                    "roundedDownFees != standardResultFees (computeAddLiquiditySingleTokenExactOut)"
                );
            }
        }
    }

    function testComputeRemoveLiquiditySingleTokenExactOut__Fuzz(
        uint256[2] calldata rawBalances,
        uint256 rawTokenOutIndex,
        uint256 rawAmountOut,
        uint256 rawTotalSupply,
        uint64 rawSwapFee,
        bool flipBit
    ) external view {
        uint256[] memory balances = new uint256[](2);
        for (uint256 i = 0; i < balances.length; ++i) {
            balances[i] = bound(rawBalances[i], MIN_BALANCE, MAX_AMOUNT);
        }
        uint256 tokenOutIndex = bound(rawTokenOutIndex, 0, 1);
        uint256 amountOut = bound(rawAmountOut, MIN_AMOUNT, MAX_AMOUNT / 4);
        uint256 totalSupply = bound(rawTotalSupply, amountOut * 4, MAX_AMOUNT);
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

        uint256 roundedUpAmountOut = flipBit ? amountOut + 1 : amountOut;
        uint256 roundedDownAmountOut = flipBit ? amountOut - 1 : amountOut;

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

        if (flipBit) {
            assertApproxEqAbs(
                roundedUpBptAmountIn,
                standardResultBptAmountIn,
                DELTA,
                "roundedUpBptAmountIn != standardResultBptAmountIn with DELTA (computeRemoveLiquiditySingleTokenExactOut)"
            );
            assertApproxEqAbs(
                roundedDownBptAmountIn,
                standardResultBptAmountIn,
                DELTA,
                "roundedDownBptAmountIn != standardResultBptAmountIn with DELTA (computeRemoveLiquiditySingleTokenExactOut)"
            );

            for (uint256 i = 0; i < balances.length; ++i) {
                assertApproxEqAbs(
                    roundedUpFees[i],
                    standardResultFees[i],
                    DELTA,
                    "roundedUpFees != standardResultFees with DELTA (computeRemoveLiquiditySingleTokenExactOut)"
                );
                assertApproxEqAbs(
                    roundedDownFees[i],
                    standardResultFees[i],
                    DELTA,
                    "roundedDownFees != standardResultFees with DELTA (computeRemoveLiquiditySingleTokenExactOut)"
                );
            }
        } else {
            assertEq(
                roundedUpBptAmountIn,
                standardResultBptAmountIn,
                "roundedUpBptAmountIn != standardResultBptAmountIn (computeRemoveLiquiditySingleTokenExactOut)"
            );
            assertEq(
                roundedDownBptAmountIn,
                standardResultBptAmountIn,
                "roundedDownBptAmountIn != standardResultBptAmountIn (computeRemoveLiquiditySingleTokenExactOut)"
            );
            for (uint256 i = 0; i < balances.length; ++i) {
                assertEq(
                    roundedUpFees[i],
                    standardResultFees[i],
                    "roundedUpFees != standardResultFees (computeRemoveLiquiditySingleTokenExactOut)"
                );
                assertEq(
                    roundedDownFees[i],
                    standardResultFees[i],
                    "roundedDownFees != standardResultFees (computeRemoveLiquiditySingleTokenExactOut)"
                );
            }
        }
    }

    function testComputeRemoveLiquiditySingleTokenExactIn__Fuzz(
        uint256[2] calldata rawBalances,
        uint256 rawTokenOutIndex,
        uint256 rawBptAmountIn,
        uint256 rawTotalSupply,
        uint64 rawSwapFee,
        bool flipBit
    ) external {
        uint256[] memory balances = new uint256[](2);

        for (uint256 i = 0; i < balances.length; ++i) {
            balances[i] = bound(rawBalances[i], MIN_BALANCE, MAX_AMOUNT);
        }
        uint256 tokenOutIndex = bound(rawTokenOutIndex, 0, 1);
        uint256 bptAmountIn = bound(rawBptAmountIn, MIN_AMOUNT, MAX_AMOUNT - 1);
        uint256 totalSupply = bound(rawTotalSupply, bptAmountIn + 1, MAX_AMOUNT);
        uint256 swapFee = bound(rawSwapFee, MIN_SWAP_FEE, MAX_SWAP_FEE);

        uint256 standardResultAmountOutWithFee;
        uint256[] memory standardResultFees;

        console.log("tokenOutIndex: ", tokenOutIndex);
        console.log("bptAmountIn: ", bptAmountIn);
        console.log("totalSupply: ", totalSupply);
        console.log("swapFee: ", swapFee);

        (standardResultAmountOutWithFee, standardResultFees) = mock.computeRemoveLiquiditySingleTokenExactIn(
            balances,
            tokenOutIndex,
            bptAmountIn,
            totalSupply,
            swapFee
        );

        uint256 roundedUpBptAmountIn = flipBit ? bptAmountIn + 1 : bptAmountIn;
        uint256 roundedDownBptAmountIn = flipBit ? bptAmountIn - 1 : bptAmountIn;

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

        if (flipBit) {
            assertApproxEqAbs(
                roundedUpAmountOutWithFee,
                standardResultAmountOutWithFee,
                DELTA,
                "roundedUpAmountOutWithFee != standardResultAmountOutWithFee with DELTA (computeRemoveLiquiditySingleTokenExactIn)"
            );
            assertApproxEqAbs(
                roundedDownAmountOutWithFee,
                standardResultAmountOutWithFee,
                DELTA,
                "roundedDownAmountOutWithFee != standardResultAmountOutWithFee with DELTA (computeRemoveLiquiditySingleTokenExactIn)"
            );

            for (uint256 i = 0; i < balances.length; ++i) {
                assertApproxEqAbs(
                    roundedUpFees[i],
                    standardResultFees[i],
                    DELTA,
                    "roundedUpFees != standardResultFees with DELTA (computeRemoveLiquiditySingleTokenExactIn)"
                );
                assertApproxEqAbs(
                    roundedDownFees[i],
                    standardResultFees[i],
                    DELTA,
                    "roundedDownFees != standardResultFees with DELTA (computeRemoveLiquiditySingleTokenExactIn)"
                );
            }
        } else {
            assertEq(
                roundedUpAmountOutWithFee,
                standardResultAmountOutWithFee,
                "roundedUpAmountOutWithFee != standardResultAmountOutWithFee (computeRemoveLiquiditySingleTokenExactIn)"
            );
            assertEq(
                roundedDownAmountOutWithFee,
                standardResultAmountOutWithFee,
                "roundedDownAmountOutWithFee != standardResultAmountOutWithFee (computeRemoveLiquiditySingleTokenExactIn)"
            );
            for (uint256 i = 0; i < balances.length; ++i) {
                assertEq(
                    roundedUpFees[i],
                    standardResultFees[i],
                    "roundedUpFees != standardResultFees (computeRemoveLiquiditySingleTokenExactIn)"
                );
                assertEq(
                    roundedDownFees[i],
                    standardResultFees[i],
                    "roundedDownFees != standardResultFees (computeRemoveLiquiditySingleTokenExactIn)"
                );
            }
        }
    }
}
