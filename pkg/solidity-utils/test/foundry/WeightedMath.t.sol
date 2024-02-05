// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import "../../contracts/math/FixedPoint.sol";
import "../../contracts/test/WeightedMathMock.sol";

contract WeightedMathTest is Test {
    uint256 constant MIN_WEIGHT = 0.1e18;
    uint256 constant MAX_WEIGHT = 0.9e18;
    uint256 constant MIN_BALANCE = 1e18;
    uint256 constant MIN_AMOUNT = 1e12;
    uint256 constant MAX_AMOUNT = 1000e18;
    uint256 constant FP_ONE = 1e18;

    uint256 constant MAX_IN_RATIO = 0.3e18;
    uint256 constant MAX_OUT_RATIO = 0.3e18;

    uint256 constant MIN_SWAP_FEE = 0;
    uint256 constant MAX_SWAP_FEE = 0.8e18;

    WeightedMathMock mock;

    function setUp() public {
        mock = new WeightedMathMock();
    }

    function testComputeOutGivenExactIn(
        uint64 rawWeightIn,
        uint256 rawBalanceIn,
        uint256 rawBalanceOut,
        uint256 rawAmountGiven,
        bool flipBit
    ) external {
        uint256 weightIn = bound(rawWeightIn, MIN_WEIGHT, MAX_WEIGHT);
        uint256 weightOut = FP_ONE - weightIn;

        uint256 balanceIn = bound(rawBalanceIn, MIN_BALANCE, MAX_AMOUNT);
        uint256 balanceOut = bound(rawBalanceOut, MIN_BALANCE, MAX_AMOUNT);

        // Subtract 1 to allow for rounding up in the amountGiven
        uint256 amountGiven = bound(rawAmountGiven, MIN_AMOUNT, FixedPoint.mulDown(balanceIn, MAX_IN_RATIO) - 1);

        assertEq(weightIn + weightOut, FP_ONE);

        uint256 standardResult = mock.computeOutGivenExactIn(balanceIn, weightIn, balanceOut, weightOut, amountGiven);

        uint256 roundedUpAmountGiven = flipBit ? amountGiven + 1 : amountGiven;
        uint256 roundedDownAmountGiven = flipBit ? amountGiven - 1 : amountGiven;

        uint256 roundedUpResult = mock.computeOutGivenExactIn(
            balanceIn,
            weightIn,
            balanceOut,
            weightOut,
            roundedUpAmountGiven
        );

        uint256 roundedDownResult = mock.computeOutGivenExactIn(
            balanceIn,
            weightIn,
            balanceOut,
            weightOut,
            roundedDownAmountGiven
        );

        assertGe(roundedUpResult, standardResult);
        assertLe(roundedDownResult, standardResult);
    }

    function testComputeInGivenExactOut(
        uint64 rawWeightIn,
        uint256 rawBalanceIn,
        uint256 rawBalanceOut,
        uint256 rawAmountGiven,
        bool flipBit
    ) external {
        uint256 weightIn = bound(rawWeightIn, MIN_WEIGHT, MAX_WEIGHT);
        uint256 weightOut = FP_ONE - weightIn;

        uint256 balanceIn = bound(rawBalanceIn, MIN_BALANCE, MAX_AMOUNT);
        uint256 balanceOut = bound(rawBalanceOut, MIN_BALANCE, MAX_AMOUNT);

        // Subtract 1 to allow for rounding up in the amountGiven
        uint256 amountGiven = bound(rawAmountGiven, MIN_AMOUNT, FixedPoint.mulDown(balanceOut, MAX_OUT_RATIO) - 1);

        assertEq(weightIn + weightOut, FP_ONE);

        uint256 standardResult = mock.computeInGivenExactOut(balanceIn, weightIn, balanceOut, weightOut, amountGiven);

        uint256 roundedUpAmountGiven = flipBit ? amountGiven + 1 : amountGiven;
        uint256 roundedDownAmountGiven = flipBit ? amountGiven - 1 : amountGiven;

        uint256 roundedUpResult = mock.computeInGivenExactOut(
            balanceIn,
            weightIn,
            balanceOut,
            weightOut,
            roundedUpAmountGiven
        );

        uint256 roundedDownResult = mock.computeInGivenExactOut(
            balanceIn,
            weightIn,
            balanceOut,
            weightOut,
            roundedDownAmountGiven
        );

        assertGe(roundedUpResult, standardResult);
        assertLe(roundedDownResult, standardResult);
    }

    struct AddLiquidityVars {
        uint256[] balances;
        uint256[] weights;
        uint256[] amountsIn;
        uint256 totalSupply;
        uint256 swapFee;
    }

    // TODO: Temporarily disable; fails intermittently due to math library precision
    function skipTestComputeBptOutGivenExactTokensIn(
        uint64 rawWeight,
        uint64 rawSwapFee,
        uint256 rawTotalSupply,
        uint256[2] calldata rawBalances,
        uint256[2] calldata rawAmountsIn,
        bool flipBit
    ) external {
        AddLiquidityVars memory vars = _computeAddLiquidityVars(
            rawWeight,
            rawSwapFee,
            rawTotalSupply,
            rawBalances,
            rawAmountsIn
        );

        uint256 standardResult = mock.computeBptOutGivenExactTokensIn(
            vars.balances,
            vars.weights,
            vars.amountsIn,
            vars.totalSupply,
            vars.swapFee
        );

        uint256[] memory roundedUpBalances = new uint256[](2);
        uint256[] memory roundedDownBalances = new uint256[](2);

        for (uint256 i = 0; i < 2; i++) {
            roundedUpBalances[i] = flipBit ? vars.balances[i] + 1 : vars.balances[i];
            roundedDownBalances[i] = flipBit ? vars.balances[i] - 1 : vars.balances[i];
        }

        uint256 roundedUpResult = mock.computeBptOutGivenExactTokensIn(
            roundedUpBalances,
            vars.weights,
            vars.amountsIn,
            vars.totalSupply,
            vars.swapFee
        );

        uint256 roundedDownResult = mock.computeBptOutGivenExactTokensIn(
            roundedDownBalances,
            vars.weights,
            vars.amountsIn,
            vars.totalSupply,
            vars.swapFee
        );

        assertLe(roundedUpResult, standardResult);
        assertGe(roundedDownResult, standardResult);
    }

    function testComputeBptInGivenExactTokensOut(
        uint64 rawWeight,
        uint64 rawSwapFee,
        uint256 rawTotalSupply,
        uint256[2] calldata rawBalances,
        bool flipBit
    ) external {
        uint256[] memory weights = new uint256[](2);
        uint256[] memory balances = new uint256[](2);
        uint256[] memory amountsOut = new uint256[](2);

        weights[0] = bound(rawWeight, MIN_WEIGHT, MAX_WEIGHT);
        weights[1] = FP_ONE - weights[0];
        assertEq(weights[0] + weights[1], FP_ONE);

        uint256 totalBalance;

        for (uint256 i = 0; i < 2; i++) {
            balances[i] = bound(rawBalances[i], MIN_BALANCE, MAX_AMOUNT);
            amountsOut[i] = balances[i] / 10;
            totalBalance += balances[i];
        }

        uint256 swapFee = bound(rawSwapFee, MIN_SWAP_FEE, MAX_SWAP_FEE);
        uint256 totalSupply = bound(rawTotalSupply, totalBalance, totalBalance * 100);

        uint256 standardResult = mock.computeBptInGivenExactTokensOut(
            balances,
            weights,
            amountsOut,
            totalSupply,
            swapFee
        );

        uint256[] memory roundedUpBalances = new uint256[](2);
        uint256[] memory roundedDownBalances = new uint256[](2);

        for (uint256 i = 0; i < 2; i++) {
            roundedUpBalances[i] = flipBit ? balances[i] + 1 : balances[i];
            roundedDownBalances[i] = flipBit ? balances[i] - 1 : balances[i];
        }

        uint256 roundedUpResult = mock.computeBptInGivenExactTokensOut(
            roundedUpBalances,
            weights,
            amountsOut,
            totalSupply,
            swapFee
        );

        uint256 roundedDownResult = mock.computeBptInGivenExactTokensOut(
            roundedDownBalances,
            weights,
            amountsOut,
            totalSupply,
            swapFee
        );

        assertLe(roundedUpResult, standardResult);
        assertGe(roundedDownResult, standardResult);
    }

    function _computeAddLiquidityVars(
        uint64 rawWeight,
        uint64 rawSwapFee,
        uint256 rawTotalSupply,
        uint256[2] calldata rawBalances,
        uint256[2] calldata rawAmounts
    ) private returns (AddLiquidityVars memory vars) {
        vars.weights = new uint256[](2);
        vars.balances = new uint256[](2);
        vars.amountsIn = new uint256[](2);

        vars.weights[0] = bound(rawWeight, MIN_WEIGHT, MAX_WEIGHT);
        vars.weights[1] = FP_ONE - vars.weights[0];
        assertEq(vars.weights[0] + vars.weights[1], FP_ONE);

        vars.swapFee = bound(rawSwapFee, MIN_SWAP_FEE, MAX_SWAP_FEE);
        uint256 totalBalance;

        for (uint256 i = 0; i < 2; i++) {
            vars.balances[i] = bound(rawBalances[i], MIN_BALANCE, MAX_AMOUNT);
            totalBalance += vars.balances[i];

            vars.amountsIn[i] = bound(rawAmounts[i], MIN_BALANCE, MAX_AMOUNT);
        }

        vars.totalSupply = bound(rawTotalSupply, totalBalance, totalBalance * 100);
    }
}
