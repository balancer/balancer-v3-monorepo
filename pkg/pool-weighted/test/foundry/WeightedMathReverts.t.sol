// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { WeightedMath } from "@balancer-labs/v3-solidity-utils/contracts/math/WeightedMath.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

/**
 * @notice Minimal, security-relevant tests to cover WeightedMath's revert branches.
 * @dev These are important guardrails (ratio limits + zero-invariant) and were previously uncovered in LCOV.
 */
contract WeightedMathRevertsTest is Test {
    using FixedPoint for uint256;

    uint256 private constant MAX_IN_RATIO = 30e16; // must match WeightedMath._MAX_IN_RATIO
    uint256 private constant MAX_OUT_RATIO = 30e16; // must match WeightedMath._MAX_OUT_RATIO

    function test_computeInvariantUp_revertsOnZeroInvariant() public {
        // Use a single-token edge case so the exponent is exactly 1.0 (FixedPoint.ONE),
        // making powUp(0, 1.0) == 0 and forcing invariant == 0.
        uint256[] memory w = new uint256[](1);
        w[0] = FixedPoint.ONE;

        uint256[] memory b = new uint256[](1);
        b[0] = 0;

        vm.expectRevert(WeightedMath.ZeroInvariant.selector);
        WeightedMath.computeInvariantUp(w, b);
    }

    function test_computeInvariantDown_revertsOnZeroInvariant() public {
        // Mirror the Up test: ensure the Down variant also hits the ZeroInvariant revert branch.
        uint256[] memory w = new uint256[](1);
        w[0] = FixedPoint.ONE;

        uint256[] memory b = new uint256[](1);
        b[0] = 0;

        vm.expectRevert(WeightedMath.ZeroInvariant.selector);
        WeightedMath.computeInvariantDown(w, b);
    }

    function test_computeOutGivenExactIn_revertsOnMaxInRatio() public {
        uint256 balanceIn = 1e18;
        uint256 balanceOut = 1e18;
        uint256 weightIn = 50e16;
        uint256 weightOut = 50e16;

        uint256 maxAmountIn = balanceIn.mulDown(MAX_IN_RATIO);
        uint256 amountIn = maxAmountIn + 1;

        vm.expectRevert(WeightedMath.MaxInRatio.selector);
        WeightedMath.computeOutGivenExactIn(balanceIn, weightIn, balanceOut, weightOut, amountIn);
    }

    function test_computeInGivenExactOut_revertsOnMaxOutRatio() public {
        uint256 balanceIn = 1e18;
        uint256 balanceOut = 1e18;
        uint256 weightIn = 50e16;
        uint256 weightOut = 50e16;

        uint256 maxAmountOut = balanceOut.mulDown(MAX_OUT_RATIO);
        uint256 amountOut = maxAmountOut + 1;

        vm.expectRevert(WeightedMath.MaxOutRatio.selector);
        WeightedMath.computeInGivenExactOut(balanceIn, weightIn, balanceOut, weightOut, amountOut);
    }
}
