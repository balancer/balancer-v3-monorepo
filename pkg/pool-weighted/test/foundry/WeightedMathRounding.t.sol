// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { WeightedMath } from "@balancer-labs/v3-solidity-utils/contracts/math/WeightedMath.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { WeightedPoolContractsDeployer } from "./utils/WeightedPoolContractsDeployer.sol";
import { WeightedMathMock } from "../../contracts/test/WeightedMathMock.sol";

contract WeightedMathRoundingTest is Test, WeightedPoolContractsDeployer {
    using FixedPoint for uint256;
    using ArrayHelpers for *;

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

    uint256 constant MIN_SWAP_AMOUNT = 1e6;
    uint256 constant MIN_BALANCE_ROUNDING_TEST = 1e5;
    uint256 constant MAX_BALANCE_ROUNDING_TEST = 1e30;

    uint256 constant MIN_TEST_RATE = 1e18;
    uint256 constant MAX_TEST_RATE = 10e18;
    uint256 constant MIN_TEST_WEIGHT = 3e16;
    uint256 constant MAX_TEST_WEIGHT = 97e16;

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

    function testRoundingBalancesExactIn__Fuzz(
        uint256 balanceRaw0,
        uint256 rate0,
        uint256 balanceRaw1,
        uint256 rate1,
        uint256 weight0,
        uint256 amountIn0Scaled18
    ) public pure {
        balanceRaw0 = bound(balanceRaw0, MIN_SWAP_AMOUNT.divUp(MAX_IN_RATIO), MAX_BALANCE_ROUNDING_TEST);
        rate0 = bound(rate0, MIN_TEST_RATE, MAX_TEST_RATE);
        balanceRaw1 = bound(balanceRaw1, MIN_BALANCE_ROUNDING_TEST, MAX_BALANCE_ROUNDING_TEST);
        rate1 = bound(rate1, MIN_TEST_RATE, MAX_TEST_RATE);
        weight0 = bound(weight0, MIN_TEST_WEIGHT, MAX_TEST_WEIGHT);
        uint256 weight1 = FixedPoint.ONE - weight0;
        uint256[] memory weights = [weight0, weight1].toMemoryArray();
        amountIn0Scaled18 = bound(amountIn0Scaled18, MIN_SWAP_AMOUNT, balanceRaw0.mulDown(rate0).mulDown(MAX_IN_RATIO));

        _testExactIn(balanceRaw0, rate0, balanceRaw1, rate1, weights, amountIn0Scaled18);
    }

    function testRoundingBalancesExactIn8020__Fuzz(
        uint256 balanceRaw0,
        uint256 rate0,
        uint256 balanceRaw1,
        uint256 rate1,
        uint256 amountIn0Scaled18
    ) public pure {
        balanceRaw0 = bound(balanceRaw0, MIN_SWAP_AMOUNT.divUp(MAX_IN_RATIO), MAX_BALANCE_ROUNDING_TEST);
        rate0 = bound(rate0, MIN_TEST_RATE, MAX_TEST_RATE);
        balanceRaw1 = bound(balanceRaw1, MIN_BALANCE_ROUNDING_TEST, MAX_BALANCE_ROUNDING_TEST);
        rate1 = bound(rate1, MIN_TEST_RATE, MAX_TEST_RATE);
        uint256[] memory weights = [uint256(80e16), uint256(20e16)].toMemoryArray();
        amountIn0Scaled18 = bound(amountIn0Scaled18, MIN_SWAP_AMOUNT, balanceRaw0.mulDown(rate0).mulDown(MAX_IN_RATIO));

        _testExactIn(balanceRaw0, rate0, balanceRaw1, rate1, weights, amountIn0Scaled18);
    }

    function testRoundingBalancesExactIn2080__Fuzz(
        uint256 balanceRaw0,
        uint256 rate0,
        uint256 balanceRaw1,
        uint256 rate1,
        uint256 amountIn0Scaled18
    ) public pure {
        balanceRaw0 = bound(balanceRaw0, MIN_SWAP_AMOUNT.divUp(MAX_IN_RATIO), MAX_BALANCE_ROUNDING_TEST);
        rate0 = bound(rate0, MIN_TEST_RATE, MAX_TEST_RATE);
        balanceRaw1 = bound(balanceRaw1, MIN_BALANCE_ROUNDING_TEST, MAX_BALANCE_ROUNDING_TEST);
        rate1 = bound(rate1, MIN_TEST_RATE, MAX_TEST_RATE);
        uint256[] memory weights = [uint256(20e16), uint256(80e16)].toMemoryArray();
        amountIn0Scaled18 = bound(amountIn0Scaled18, MIN_SWAP_AMOUNT, balanceRaw0.mulDown(rate0).mulDown(MAX_IN_RATIO));

        _testExactIn(balanceRaw0, rate0, balanceRaw1, rate1, weights, amountIn0Scaled18);
    }

    function testRoundingBalancesExactIn5050__Fuzz(
        uint256 balanceRaw0,
        uint256 rate0,
        uint256 balanceRaw1,
        uint256 rate1,
        uint256 amountIn0Scaled18
    ) public pure {
        balanceRaw0 = bound(balanceRaw0, MIN_SWAP_AMOUNT.divUp(MAX_IN_RATIO), MAX_BALANCE_ROUNDING_TEST);
        rate0 = bound(rate0, MIN_TEST_RATE, MAX_TEST_RATE);
        balanceRaw1 = bound(balanceRaw1, MIN_BALANCE_ROUNDING_TEST, MAX_BALANCE_ROUNDING_TEST);
        rate1 = bound(rate1, MIN_TEST_RATE, MAX_TEST_RATE);
        uint256[] memory weights = [uint256(50e16), uint256(50e16)].toMemoryArray();
        amountIn0Scaled18 = bound(amountIn0Scaled18, MIN_SWAP_AMOUNT, balanceRaw0.mulDown(rate0).mulDown(MAX_IN_RATIO));

        _testExactIn(balanceRaw0, rate0, balanceRaw1, rate1, weights, amountIn0Scaled18);
    }

    function _testExactIn(
        uint256 balanceRaw0,
        uint256 rate0,
        uint256 balanceRaw1,
        uint256 rate1,
        uint256[] memory weights,
        uint256 amountIn0Scaled18
    ) internal pure {
        (uint256 tokenIndexIn, uint256 tokenIndexOut) = (0, 1);
        uint256[] memory balancesScaled18RoundDown = new uint256[](2);
        balancesScaled18RoundDown[0] = balanceRaw0.mulDown(rate0);
        balancesScaled18RoundDown[1] = balanceRaw1.mulDown(rate1);

        uint256 amountOutScaled18BalancesRoundDown = WeightedMath.computeOutGivenExactIn(
            balancesScaled18RoundDown[tokenIndexIn],
            weights[tokenIndexIn],
            balancesScaled18RoundDown[tokenIndexOut],
            weights[tokenIndexOut],
            amountIn0Scaled18
        );

        vm.assume(amountOutScaled18BalancesRoundDown >= MIN_SWAP_AMOUNT);

        uint256[] memory balancesScaled18RoundAlt = new uint256[](2);
        balancesScaled18RoundAlt[0] = balanceRaw0.mulUp(rate0);
        balancesScaled18RoundAlt[1] = balanceRaw1.mulDown(rate1);

        uint256 amountOutScaled18BalancesRoundAlt = WeightedMath.computeOutGivenExactIn(
            balancesScaled18RoundAlt[tokenIndexIn],
            weights[tokenIndexIn],
            balancesScaled18RoundAlt[tokenIndexOut],
            weights[tokenIndexOut],
            amountIn0Scaled18
        );

        // Amount out scaled with alt rounding should not be higher (worse for the vault) than regular rounding.
        assertLe(
            amountOutScaled18BalancesRoundAlt,
            amountOutScaled18BalancesRoundDown,
            "Alt rounding returned higher amounts out"
        );
        assertApproxEqRel(
            amountOutScaled18BalancesRoundAlt,
            amountOutScaled18BalancesRoundDown,
            0.001e16,
            "Alt rounding returned significantly different calculated amounts out"
        );
    }

    function testRoundingBalancesExactOut__Fuzz(
        uint256 balanceRaw0,
        uint256 rate0,
        uint256 balanceRaw1,
        uint256 rate1,
        uint256 weight0,
        uint256 amountOut1Scaled18
    ) public pure {
        balanceRaw0 = bound(balanceRaw0, MIN_BALANCE_ROUNDING_TEST, MAX_BALANCE_ROUNDING_TEST);
        rate0 = bound(rate0, MIN_TEST_RATE, MAX_TEST_RATE);
        rate1 = bound(rate1, MIN_TEST_RATE, MAX_TEST_RATE);
        // Need small buffer here, otherwise the max amountOut1Scaled18 will be < MIN_SWAP_AMOUNT below.
        balanceRaw1 = bound(
            balanceRaw1,
            (MIN_SWAP_AMOUNT + 1).divUp(rate1).divUp(MAX_OUT_RATIO),
            MAX_BALANCE_ROUNDING_TEST
        );
        weight0 = bound(weight0, MIN_TEST_WEIGHT, MAX_TEST_WEIGHT);
        uint256 weight1 = FixedPoint.ONE - weight0;
        uint256[] memory weights = [weight0, weight1].toMemoryArray();

        // Can't get more than the balance of the output token
        amountOut1Scaled18 = bound(
            amountOut1Scaled18,
            MIN_SWAP_AMOUNT,
            balanceRaw1.mulDown(rate1).mulDown(MAX_OUT_RATIO)
        );

        _testExactOut(balanceRaw0, rate0, balanceRaw1, rate1, weights, amountOut1Scaled18);
    }

    function testRoundingBalancesExactOut8020__Fuzz(
        uint256 balanceRaw0,
        uint256 rate0,
        uint256 balanceRaw1,
        uint256 rate1,
        uint256 amountOut1Scaled18
    ) public pure {
        balanceRaw0 = bound(balanceRaw0, MIN_BALANCE_ROUNDING_TEST, MAX_BALANCE_ROUNDING_TEST);
        rate0 = bound(rate0, MIN_TEST_RATE, MAX_TEST_RATE);
        rate1 = bound(rate1, MIN_TEST_RATE, MAX_TEST_RATE);
        // Need small buffer here, otherwise the max amountOut1Scaled18 will be < MIN_SWAP_AMOUNT below.
        balanceRaw1 = bound(
            balanceRaw1,
            (MIN_SWAP_AMOUNT + 1).divUp(rate1).divUp(MAX_OUT_RATIO),
            MAX_BALANCE_ROUNDING_TEST
        );
        uint256[] memory weights = [uint256(80e16), uint256(20e16)].toMemoryArray();
        // Can't get more than the balance of the output token
        amountOut1Scaled18 = bound(
            amountOut1Scaled18,
            MIN_SWAP_AMOUNT,
            balanceRaw1.mulDown(rate1).mulDown(MAX_OUT_RATIO)
        );

        _testExactOut(balanceRaw0, rate0, balanceRaw1, rate1, weights, amountOut1Scaled18);
    }

    function testRoundingBalancesExactOut2080__Fuzz(
        uint256 balanceRaw0,
        uint256 rate0,
        uint256 balanceRaw1,
        uint256 rate1,
        uint256 amountOut1Scaled18
    ) public pure {
        balanceRaw0 = bound(balanceRaw0, MIN_BALANCE_ROUNDING_TEST, MAX_BALANCE_ROUNDING_TEST);
        rate0 = bound(rate0, MIN_TEST_RATE, MAX_TEST_RATE);
        rate1 = bound(rate1, MIN_TEST_RATE, MAX_TEST_RATE);
        // Need small buffer here, otherwise the max amountOut1Scaled18 will be < MIN_SWAP_AMOUNT below.
        balanceRaw1 = bound(
            balanceRaw1,
            (MIN_SWAP_AMOUNT + 1).divUp(rate1).divUp(MAX_OUT_RATIO),
            MAX_BALANCE_ROUNDING_TEST
        );
        uint256[] memory weights = [uint256(20e16), uint256(80e16)].toMemoryArray();
        // Can't get more than the balance of the output token
        amountOut1Scaled18 = bound(
            amountOut1Scaled18,
            MIN_SWAP_AMOUNT,
            balanceRaw1.mulDown(rate1).mulDown(MAX_OUT_RATIO)
        );

        _testExactOut(balanceRaw0, rate0, balanceRaw1, rate1, weights, amountOut1Scaled18);
    }

    function testRoundingBalancesExactOut5050__Fuzz(
        uint256 balanceRaw0,
        uint256 rate0,
        uint256 balanceRaw1,
        uint256 rate1,
        uint256 amountOut1Scaled18
    ) public pure {
        balanceRaw0 = bound(balanceRaw0, MIN_BALANCE_ROUNDING_TEST, MAX_BALANCE_ROUNDING_TEST);
        rate0 = bound(rate0, MIN_TEST_RATE, MAX_TEST_RATE);
        rate1 = bound(rate1, MIN_TEST_RATE, MAX_TEST_RATE);
        // Need small buffer here, otherwise the max amountOut1Scaled18 will be < MIN_SWAP_AMOUNT below.
        balanceRaw1 = bound(
            balanceRaw1,
            (MIN_SWAP_AMOUNT + 1).divUp(rate1).divUp(MAX_OUT_RATIO),
            MAX_BALANCE_ROUNDING_TEST
        );
        uint256[] memory weights = [uint256(50e16), uint256(50e16)].toMemoryArray();
        // Can't get more than the balance of the output token
        amountOut1Scaled18 = bound(
            amountOut1Scaled18,
            MIN_SWAP_AMOUNT,
            balanceRaw1.mulDown(rate1).mulDown(MAX_OUT_RATIO)
        );

        _testExactOut(balanceRaw0, rate0, balanceRaw1, rate1, weights, amountOut1Scaled18);
    }

    function _testExactOut(
        uint256 balanceRaw0,
        uint256 rate0,
        uint256 balanceRaw1,
        uint256 rate1,
        uint256[] memory weights,
        uint256 amountOut1Scaled18
    ) internal pure {
        (uint256 tokenIndexIn, uint256 tokenIndexOut) = (0, 1);

        uint256[] memory balancesScaled18RoundDown = new uint256[](2);
        balancesScaled18RoundDown[0] = balanceRaw0.mulDown(rate0);
        balancesScaled18RoundDown[1] = balanceRaw1.mulDown(rate1);

        uint256 amountInScaled18BalancesRoundDown = WeightedMath.computeInGivenExactOut(
            balancesScaled18RoundDown[tokenIndexIn],
            weights[tokenIndexIn],
            balancesScaled18RoundDown[tokenIndexOut],
            weights[tokenIndexOut],
            amountOut1Scaled18
        );

        vm.assume(amountInScaled18BalancesRoundDown >= MIN_SWAP_AMOUNT);

        uint256[] memory balancesScaled18RoundAlt = new uint256[](2);
        balancesScaled18RoundAlt[0] = balanceRaw0.mulUp(rate0);
        balancesScaled18RoundAlt[1] = balanceRaw1.mulDown(rate1);

        uint256 amountInScaled18BalancesRoundAlt = WeightedMath.computeInGivenExactOut(
            balancesScaled18RoundAlt[tokenIndexIn],
            weights[tokenIndexIn],
            balancesScaled18RoundAlt[tokenIndexOut],
            weights[tokenIndexOut],
            amountOut1Scaled18
        );

        // Amount in scaled with alt rounding not be lower (worse for the vault) than regular rounding.
        assertGe(
            amountInScaled18BalancesRoundAlt,
            amountInScaled18BalancesRoundDown,
            "Alt rounding returned lower amounts in"
        );

        assertApproxEqRel(
            amountInScaled18BalancesRoundAlt,
            amountInScaled18BalancesRoundDown,
            0.01e16,
            "Alt rounding returned significantly different calculated amounts in"
        );
    }
}
