// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { WeightedMath } from "@balancer-labs/v3-solidity-utils/contracts/math/WeightedMath.sol";

import { WeightedMathMock } from "../../contracts/test/WeightedMathMock.sol";
import { WeightedPoolContractsDeployer } from "./utils/WeightedPoolContractsDeployer.sol";

contract WeightedMathRoundingTest is Test, WeightedPoolContractsDeployer {
    using FixedPoint for uint256;

    uint256 constant MIN_ABS_WEIGHT = 1e16; // 1%

    uint256 constant MIN_WEIGHT = 10e16; // 10%
    uint256 constant MAX_WEIGHT = 90e16; // 90%
    uint256 constant MIN_BALANCE = 1e18;
    uint256 constant MIN_AMOUNT = 1e12;
    uint256 constant MAX_AMOUNT = 1000e18;
    uint256 constant FP_ONE = 1e18;

    uint256 constant MAX_IN_RATIO = 0.3e18;
    uint256 constant MAX_OUT_RATIO = 0.3e18;

    uint256 constant MIN_SWAP_FEE = 0;
    uint256 constant MAX_SWAP_FEE = 80e16; // 80%
    uint256 constant DELTA = 1e8;

    WeightedMathMock mock;

    function setUp() public {
        mock = deployWeightedMathMock();
    }

    function testComputeOutGivenExactIn__Fuzz(
        uint64 rawWeightIn,
        uint256 rawBalanceIn,
        uint256 rawBalanceOut,
        uint256 rawAmountGiven,
        bool flipBit
    ) external view {
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

        if (flipBit) {
            assertGe(roundedUpResult, standardResult, "roundedUpResult < standardResult (computeOutGivenExactIn)");
            assertLe(roundedDownResult, standardResult, "roundedDownResult > standardResult (computeOutGivenExactIn)");
        } else {
            assertEq(roundedUpResult, standardResult, "roundedUpResult != standardResult (computeOutGivenExactIn)");
            assertEq(roundedDownResult, standardResult, "roundedDownResult != standardResult (computeOutGivenExactIn)");
        }
    }

    function testComputeInGivenExactOut__Fuzz(
        uint64 rawWeightIn,
        uint256 rawBalanceIn,
        uint256 rawBalanceOut,
        uint256 rawAmountGiven,
        bool flipBit
    ) external view {
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

        if (flipBit) {
            assertGe(roundedUpResult, standardResult, "roundedUpResult < standardResult (computeInGivenExactOut)");
            assertLe(roundedDownResult, standardResult, "roundedDownResult > standardResult (computeInGivenExactOut)");
        } else {
            assertEq(roundedUpResult, standardResult, "roundedUpResult != standardResult (computeInGivenExactOut)");
            assertEq(roundedDownResult, standardResult, "roundedDownResult != standardResult (computeInGivenExactOut)");
        }
    }

    function testComputeBalanceOutGivenInvariantRounding__Fuzz(
        uint256 invariantRatio,
        uint256 weight,
        uint256 currentBalance
    ) external pure {
        invariantRatio = bound(invariantRatio, WeightedMath._MIN_INVARIANT_RATIO, WeightedMath._MAX_INVARIANT_RATIO);
        weight = bound(weight, MIN_WEIGHT, FixedPoint.ONE - MIN_ABS_WEIGHT);
        currentBalance = bound(currentBalance, 1e6, 1e26);

        _testComputeBalanceGivenOutRounding(invariantRatio, weight, currentBalance);
    }

    function testComputeBalanceOutGivenInvariantRoundingExtremeWeights__Fuzz(
        uint256 invariantRatio,
        uint256 weight,
        uint256 currentBalance
    ) external pure {
        invariantRatio = bound(invariantRatio, WeightedMath._MIN_INVARIANT_RATIO, WeightedMath._MAX_INVARIANT_RATIO);
        // * 2 to avoid overflow errors.
        weight = bound(weight, MIN_ABS_WEIGHT * 2, FixedPoint.ONE - MIN_ABS_WEIGHT);
        currentBalance = bound(currentBalance, 1e10, 100e18);

        _testComputeBalanceGivenOutRounding(invariantRatio, weight, currentBalance);
    }

    function testComputeBalanceOutGivenInvariantRoundingAdds__Fuzz(
        uint256 invariantRatio,
        uint256 weight,
        uint256 currentBalance
    ) external pure {
        invariantRatio = bound(invariantRatio, FixedPoint.ONE, WeightedMath._MAX_INVARIANT_RATIO);
        weight = bound(weight, MIN_WEIGHT, FixedPoint.ONE - MIN_ABS_WEIGHT);
        currentBalance = bound(currentBalance, 1e6, 1e26);

        _testComputeBalanceGivenOutRounding(invariantRatio, weight, currentBalance);
    }

    function testComputeBalanceOutGivenInvariantRoundingRemoves__Fuzz(
        uint256 invariantRatio,
        uint256 weight,
        uint256 currentBalance
    ) external pure {
        invariantRatio = bound(invariantRatio, WeightedMath._MIN_INVARIANT_RATIO, FixedPoint.ONE);
        weight = bound(weight, MIN_WEIGHT, FixedPoint.ONE - MIN_ABS_WEIGHT);
        currentBalance = bound(currentBalance, 1e6, 1e26);

        _testComputeBalanceGivenOutRounding(invariantRatio, weight, currentBalance);
    }

    function _testComputeBalanceGivenOutRounding(
        uint256 invariantRatio,
        uint256 weight,
        uint256 currentBalance
    ) internal pure {
        uint256 standardNewBalance = WeightedMath.computeBalanceOutGivenInvariant(
            currentBalance,
            weight,
            invariantRatio
        );

        uint256 newBalanceRoundDown = _computeBalanceOutGivenInvariantExpDown(currentBalance, weight, invariantRatio);

        uint256 newBalanceRoundUp = _computeBalanceOutGivenInvariantExpUp(currentBalance, weight, invariantRatio);

        assertGe(standardNewBalance, newBalanceRoundDown, "standardNewBalance < newBalanceRoundDown");
        assertGe(standardNewBalance, newBalanceRoundUp, "standardNewBalance < newBalanceRoundUp");
    }

    /// @dev Same as computeBalanceOutGivenInvariant, rounding down always
    function _computeBalanceOutGivenInvariantExpDown(
        uint256 currentBalance,
        uint256 weight,
        uint256 invariantRatio
    ) internal pure returns (uint256 newBalance) {
        uint256 balanceRatio = invariantRatio.powUp(FixedPoint.ONE.divDown(weight));

        return currentBalance.mulUp(balanceRatio);
    }

    /// @dev Same as computeBalanceOutGivenInvariant, rounding up always
    function _computeBalanceOutGivenInvariantExpUp(
        uint256 currentBalance,
        uint256 weight,
        uint256 invariantRatio
    ) internal pure returns (uint256 newBalance) {
        uint256 balanceRatio = invariantRatio.powUp(FixedPoint.ONE.divUp(weight));

        return currentBalance.mulUp(balanceRatio);
    }

    struct AddLiquidityVars {
        uint256[] balances;
        uint256[] weights;
        uint256[] amountsIn;
        uint256 totalSupply;
        uint256 swapFee;
    }
}
