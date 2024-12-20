// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { Rounding } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { StableMath } from "../../contracts/math/StableMath.sol";
import { FixedPoint } from "../../contracts/math/FixedPoint.sol";
import { ArrayHelpers } from "../../contracts/test/ArrayHelpers.sol";
import { StableMathMock } from "../../contracts/test/StableMathMock.sol";
import { ScalingHelpers } from "../../contracts/helpers/ScalingHelpers.sol";

// In the `StableMath` functions, the protocol aims for computing a value either as small as possible or as large as possible
// by means of rounding in its favor; in order to achieve this, it may use arbitrary rounding directions during the calculations.
// The objective of `StableMathTest` is to verify that the implemented rounding permutations favor the protocol more than other
// solutions (e.g., always rounding down or always rounding up).

contract StableMathTest is Test {
    using FixedPoint for uint256;
    using ArrayHelpers for *;

    uint256 constant MIN_TOKENS = 2;
    uint256 constant MAX_TOKENS = 8;
    uint256 constant NUM_TOKENS = 4;

    uint256 constant MIN_BALANCE_BASE = 1e18;
    // Max balance of a stable pool token that won't cause an overflow in stable math.
    uint256 constant MAX_BALANCE_BASE = 1_000_000_000_000_000e18;
    uint256 constant MAX_BALANCE_RATIO = 1000e16; // 1000 %

    uint256 constant MIN_AMOUNT_RATIO = 0.01e16; // 0.01 %
    uint256 constant MAX_AMOUNT_RATIO = 99.99e16; // 99.99 %

    uint256 constant MIN_AMP = StableMath.MIN_AMP * StableMath.AMP_PRECISION;
    uint256 constant MAX_AMP = StableMath.MAX_AMP * StableMath.AMP_PRECISION;

    uint256 constant MIN_BALANCE_BOUND = 1000e18;
    uint256 constant MAX_BALANCE_BOUND = 1_000_000e18;

    uint256 constant MIN_AMOUNT_IN = 0.1e18;
    uint256 constant MAX_AMOUNT_IN = 100_000e18;

    StableMathMock stableMathMock;

    function setUp() public {
        stableMathMock = new StableMathMock();
    }

    function boundTokenIndex(uint256 rawTokenIndex) internal pure returns (uint256 tokenIndex) {
        tokenIndex = rawTokenIndex % NUM_TOKENS;
    }

    function boundTokenIndexes(
        uint256 rawTokenIndexIn,
        uint256 rawTokenIndexOut
    ) internal pure returns (uint256 tokenIndexIn, uint256 tokenIndexOut) {
        tokenIndexIn = boundTokenIndex(rawTokenIndexIn);
        tokenIndexOut = boundTokenIndex(rawTokenIndexOut);
        vm.assume(tokenIndexIn != tokenIndexOut);
    }

    function boundBalances(uint256[NUM_TOKENS] calldata rawBalances) internal pure returns (uint256[] memory balances) {
        uint256 balanceBase = bound(rawBalances[0], MIN_BALANCE_BASE, MAX_BALANCE_BASE);
        balances = new uint256[](NUM_TOKENS);
        for (uint256 i = 0; i < NUM_TOKENS; ++i) {
            balances[i] = bound(rawBalances[i], balanceBase, balanceBase.mulDown(MAX_BALANCE_RATIO));
        }
    }

    function boundAmount(uint256 rawAmount, uint256 balance) internal pure returns (uint256 amount) {
        amount = bound(rawAmount, balance.mulDown(MIN_AMOUNT_RATIO), balance.mulDown(MAX_AMOUNT_RATIO));
    }

    function boundAmp(uint256 rawAmp) internal pure returns (uint256 amp) {
        amp = bound(rawAmp, MIN_AMP, MAX_AMP);
    }

    function testComputeInvariant__Fuzz(uint256 amp, uint256[NUM_TOKENS] calldata rawBalances) external view {
        amp = boundAmp(amp);
        uint256[] memory balances = boundBalances(rawBalances);
        try stableMathMock.computeInvariant(amp, balances, Rounding.ROUND_DOWN) returns (uint256) {} catch (
            bytes memory result
        ) {
            assertEq(bytes4(result), StableMath.StableInvariantDidNotConverge.selector, "Unexpected error");
            vm.assume(false);
        }

        stableMathMock.computeInvariant(amp, balances, Rounding.ROUND_DOWN);
    }

    function testComputeOutGivenExactInRounding__Fuzz(
        uint256 amp,
        uint256[NUM_TOKENS] calldata rawBalances,
        uint256 tokenIndexIn,
        uint256 tokenIndexOut,
        uint256 tokenAmountIn,
        bool[3] calldata roundingPermutation
    ) external view {
        amp = boundAmp(amp);
        uint256[] memory balances = boundBalances(rawBalances);
        (tokenIndexIn, tokenIndexOut) = boundTokenIndexes(tokenIndexIn, tokenIndexOut);
        tokenAmountIn = boundAmount(tokenAmountIn, balances[tokenIndexIn]);

        try stableMathMock.computeInvariant(amp, balances, Rounding.ROUND_DOWN) returns (uint256) {} catch (
            bytes memory result
        ) {
            assertEq(bytes4(result), StableMath.StableInvariantDidNotConverge.selector, "Unexpected error");
            vm.assume(false);
        }

        uint256 invariant = stableMathMock.computeInvariant(amp, balances, Rounding.ROUND_DOWN);

        uint256 outGivenExactIn = stableMathMock.computeOutGivenExactIn(
            amp,
            balances,
            tokenIndexIn,
            tokenIndexOut,
            tokenAmountIn,
            invariant
        );

        uint256 outGivenExactInNotPermuted = stableMathMock.mockComputeOutGivenExactIn(
            amp,
            balances,
            tokenIndexIn,
            tokenIndexOut,
            tokenAmountIn,
            invariant
        );
        uint256 outGivenExactInPermuted = stableMathMock.mockComputeOutGivenExactIn(
            amp,
            balances,
            tokenIndexIn,
            tokenIndexOut,
            tokenAmountIn,
            invariant,
            roundingPermutation
        );

        assertEq(outGivenExactIn, outGivenExactInNotPermuted, "Mock function and base one should be equivalent.");
        assertLe(
            outGivenExactIn,
            outGivenExactInPermuted,
            "Output should be less than or equal to the permuted mock value."
        );
    }

    function testComputeInGivenExactOutRounding__Fuzz(
        uint256 amp,
        uint256[NUM_TOKENS] calldata rawBalances,
        uint256 tokenIndexIn,
        uint256 tokenIndexOut,
        uint256 tokenAmountOut,
        bool[3] calldata roundingPermutation
    ) external view {
        amp = boundAmp(amp);
        uint256[] memory balances = boundBalances(rawBalances);
        (tokenIndexIn, tokenIndexOut) = boundTokenIndexes(tokenIndexIn, tokenIndexOut);
        tokenAmountOut = boundAmount(tokenAmountOut, balances[tokenIndexOut]);

        try stableMathMock.computeInvariant(amp, balances, Rounding.ROUND_DOWN) returns (uint256) {} catch (
            bytes memory result
        ) {
            assertEq(bytes4(result), StableMath.StableInvariantDidNotConverge.selector, "Unexpected error");
            vm.assume(false);
        }

        uint256 invariant = stableMathMock.computeInvariant(amp, balances, Rounding.ROUND_DOWN);

        uint256 inGivenExactOut = stableMathMock.computeInGivenExactOut(
            amp,
            balances,
            tokenIndexIn,
            tokenIndexOut,
            tokenAmountOut,
            invariant
        );

        uint256 inGivenExactOutNotPermuted = stableMathMock.mockComputeInGivenExactOut(
            amp,
            balances,
            tokenIndexIn,
            tokenIndexOut,
            tokenAmountOut,
            invariant
        );
        uint256 inGivenExactOutPermuted = stableMathMock.mockComputeInGivenExactOut(
            amp,
            balances,
            tokenIndexIn,
            tokenIndexOut,
            tokenAmountOut,
            invariant,
            roundingPermutation
        );

        assertEq(inGivenExactOut, inGivenExactOutNotPermuted, "Mock function and base one should be equivalent.");
        assertGe(
            inGivenExactOut,
            inGivenExactOutPermuted,
            "Output should be greater than or equal to the permuted mock value."
        );
    }

    function testComputeBalanceRounding__Fuzz(
        uint256 amp,
        uint256[NUM_TOKENS] calldata rawBalances,
        uint256 tokenIndex,
        bool[3] calldata roundingPermutation
    ) external view {
        amp = boundAmp(amp);
        uint256[] memory balances = boundBalances(rawBalances);

        try stableMathMock.computeInvariant(amp, balances, Rounding.ROUND_DOWN) returns (uint256) {} catch (
            bytes memory result
        ) {
            assertEq(bytes4(result), StableMath.StableInvariantDidNotConverge.selector, "Unexpected error");
            vm.assume(false);
        }

        uint256 invariant = stableMathMock.computeInvariant(amp, balances, Rounding.ROUND_DOWN);
        tokenIndex = boundTokenIndex(tokenIndex);

        uint256 balance = stableMathMock.computeBalance(amp, balances, invariant, tokenIndex);

        uint256 balanceNotPermuted = stableMathMock.mockComputeBalance(amp, balances, invariant, tokenIndex);
        uint256 balancePermuted = stableMathMock.mockComputeBalance(
            amp,
            balances,
            invariant,
            tokenIndex,
            roundingPermutation
        );

        assertEq(balance, balanceNotPermuted, "Mock function and base one should be equivalent.");
        assertGe(balance, balancePermuted, "Output should be greater than or equal to the permuted mock value.");
    }

    function testCompareComputeBalancesWithSmallDiff__Fuzz(
        uint256 amp,
        uint256[NUM_TOKENS] calldata rawBalances,
        uint256 tokenIndex,
        uint256 invariantDiff
    ) external view {
        amp = boundAmp(amp);
        uint256[] memory balances = boundBalances(rawBalances);
        tokenIndex = bound(tokenIndex, 0, NUM_TOKENS - 1);
        invariantDiff = bound(invariantDiff, 1, 100000);

        try stableMathMock.computeInvariant(amp, balances, Rounding.ROUND_DOWN) returns (uint256) {} catch (
            bytes memory result
        ) {
            assertEq(bytes4(result), StableMath.StableInvariantDidNotConverge.selector, "Unexpected error");
            vm.assume(false);
        }

        uint256 invariant = stableMathMock.computeInvariant(amp, balances, Rounding.ROUND_DOWN);
        uint256 balanceOne = stableMathMock.computeBalance(amp, balances, invariant, tokenIndex);
        uint256 balanceTwo = stableMathMock.computeBalance(amp, balances, invariant + invariantDiff, tokenIndex);

        assertGe(balanceTwo, balanceOne, "The balance should be greater or eq when the invariant is greater.");
    }

    function testComputeBalanceRounding__Fuzz(
        uint256 currentAmp,
        uint256 balance0,
        uint256 balance1,
        uint256 balance2,
        uint256 invariantRatio
    ) public view {
        currentAmp = bound(currentAmp, MIN_AMP, MAX_AMP);
        balance0 = bound(balance0, MIN_BALANCE_BOUND, MAX_BALANCE_BOUND);
        balance1 = bound(balance1, MIN_BALANCE_BOUND, MAX_BALANCE_BOUND);
        balance2 = bound(balance2, MIN_BALANCE_BOUND, MAX_BALANCE_BOUND);
        invariantRatio = bound(invariantRatio, StableMath.MIN_INVARIANT_RATIO, StableMath.MAX_INVARIANT_RATIO);
        uint256 tokenInIndex = bound(balance0 + balance1 + balance2, 0, 2);

        uint256[] memory balancesLiveScaled18 = new uint256[](3);
        balancesLiveScaled18[0] = balance0;
        balancesLiveScaled18[1] = balance1;
        balancesLiveScaled18[2] = balance2;

        try stableMathMock.computeInvariant(currentAmp, balancesLiveScaled18, Rounding.ROUND_DOWN) returns (
            uint256
        ) {} catch {
            vm.assume(false);
        }

        uint256 balanceRoundDown = StableMath.computeBalance(
            currentAmp,
            balancesLiveScaled18,
            stableMathMock.computeInvariant(currentAmp, balancesLiveScaled18, Rounding.ROUND_DOWN).mulDown(
                invariantRatio
            ),
            tokenInIndex
        );

        uint256 balanceRoundUp = StableMath.computeBalance(
            currentAmp,
            balancesLiveScaled18,
            stableMathMock.computeInvariant(currentAmp, balancesLiveScaled18, Rounding.ROUND_UP).mulUp(invariantRatio),
            tokenInIndex
        );

        assertGe(balanceRoundUp, balanceRoundDown, "Incorrect assumption");
    }

    function testComputeInvariantRatioRounding__Fuzz(
        uint256 currentAmp,
        uint256[3] memory currentBalances,
        uint256[3] memory amountsIn
    ) public view {
        currentAmp = bound(currentAmp, MIN_AMP, MAX_AMP);
        currentBalances[0] = bound(currentBalances[0], MIN_BALANCE_BOUND, MAX_BALANCE_BOUND);
        currentBalances[1] = bound(currentBalances[1], MIN_BALANCE_BOUND, MAX_BALANCE_BOUND);
        currentBalances[2] = bound(currentBalances[2], MIN_BALANCE_BOUND, MAX_BALANCE_BOUND);
        amountsIn[0] = bound(amountsIn[0], MIN_AMOUNT_IN, MAX_AMOUNT_IN);
        amountsIn[1] = bound(amountsIn[1], MIN_AMOUNT_IN, MAX_AMOUNT_IN);
        amountsIn[2] = bound(amountsIn[2], MIN_AMOUNT_IN, MAX_AMOUNT_IN);

        uint256[] memory newBalances = new uint256[](3);
        newBalances[0] = currentBalances[0] + amountsIn[0];
        newBalances[1] = currentBalances[0] + amountsIn[1];
        newBalances[2] = currentBalances[0] + amountsIn[2];

        uint256[] memory newBalancesRoundDown = new uint256[](3);
        newBalancesRoundDown[0] = newBalances[0] - 1;
        newBalancesRoundDown[1] = newBalances[1] - 1;
        newBalancesRoundDown[2] = newBalances[2] - 1;

        // Check that the invariant converges in every case.
        try stableMathMock.computeInvariant(currentAmp, currentBalances.toMemoryArray(), Rounding.ROUND_DOWN) returns (
            uint256
        ) {} catch {
            vm.assume(false);
        }

        try stableMathMock.computeInvariant(currentAmp, newBalances, Rounding.ROUND_UP) returns (uint256) {} catch {
            vm.assume(false);
        }

        try stableMathMock.computeInvariant(currentAmp, newBalancesRoundDown, Rounding.ROUND_UP) returns (
            uint256
        ) {} catch {
            vm.assume(false);
        }

        // Base case: use same rounding for balances in numerator and denominator, and use same rounding direction
        // for `computeInvariant` calls (which is accurate to 1 wei in stable math).
        uint256 currentInvariant = stableMathMock.computeInvariant(
            currentAmp,
            currentBalances.toMemoryArray(),
            Rounding.ROUND_DOWN
        );
        uint256 invariantRatioRegular = stableMathMock
            .computeInvariant(currentAmp, newBalances, Rounding.ROUND_DOWN)
            .divDown(currentInvariant);

        // Improved rounding down: use balances rounded down in numerator, and use rounding direction when calling
        // `computeInvariant` (1 wei difference).
        uint256 currentInvariantUp = stableMathMock.computeInvariant(
            currentAmp,
            currentBalances.toMemoryArray(),
            Rounding.ROUND_UP
        );
        uint256 invariantRatioDown = stableMathMock
            .computeInvariant(currentAmp, newBalancesRoundDown, Rounding.ROUND_DOWN)
            .divDown(currentInvariantUp);

        assertLe(invariantRatioDown, invariantRatioRegular, "Invariant ratio should have gone down");
    }

    function testComputeInvariantLessThenInvariantWithLargeDelta__Fuzz(
        uint256 amp,
        uint256 tokenCount,
        uint256 deltaCount,
        uint256[8] memory indexes,
        uint256[8] memory deltas,
        uint256[8] memory balancesRaw
    ) public view {
        _testComputeInvariantLessThenInvariantWithDelta(
            amp,
            tokenCount,
            deltaCount,
            indexes,
            deltas,
            balancesRaw,
            type(uint128).max
        );
    }

    function testComputeInvariantLessThenInvariantWithSmallDelta__Fuzz(
        uint256 amp,
        uint256 tokenCount,
        uint256 deltaCount,
        uint256[8] memory indexes,
        uint256[8] memory deltas,
        uint256[8] memory balancesRaw
    ) public view {
        _testComputeInvariantLessThenInvariantWithDelta(
            amp,
            tokenCount,
            deltaCount,
            indexes,
            deltas,
            balancesRaw,
            1000
        );
    }

    function _testComputeInvariantLessThenInvariantWithDelta(
        uint256 amp,
        uint256 tokenCount,
        uint256 deltaCount,
        uint256[8] memory indexes,
        uint256[8] memory deltas,
        uint256[8] memory balancesRaw,
        uint256 maxDelta
    ) internal view {
        amp = boundAmp(amp);
        tokenCount = bound(tokenCount, MIN_TOKENS, MAX_TOKENS);
        deltaCount = bound(deltaCount, 1, tokenCount);

        uint256[] memory balances = new uint256[](tokenCount);
        for (uint256 i = 0; i < tokenCount; i++) {
            balances[i] = bound(balancesRaw[i], 1, type(uint128).max);
        }

        uint256[] memory newBalances = new uint256[](tokenCount);
        ScalingHelpers.copyToArray(balances, newBalances);

        for (uint256 i = 0; i < deltaCount; i++) {
            uint256 tokenIndex = bound(indexes[i], 0, tokenCount - 1);
            uint256 delta;
            if (maxDelta > type(uint128).max - newBalances[tokenIndex]) {
                delta = bound(deltas[i], 0, type(uint128).max - newBalances[tokenIndex]);
            } else {
                delta = bound(deltas[i], 0, maxDelta);
            }
            newBalances[tokenIndex] += delta;
        }

        try stableMathMock.computeInvariant(amp, balances, Rounding.ROUND_DOWN) returns (uint256 currentInvariant) {
            try stableMathMock.computeInvariant(amp, newBalances, Rounding.ROUND_DOWN) returns (
                uint256 invariantWithDelta
            ) {
                if (invariantWithDelta < currentInvariant) {
                    assertApproxEqAbs(
                        currentInvariant,
                        invariantWithDelta,
                        1,
                        "Current invariant should be approximately equal to invariant with delta (within 1 wei)"
                    );
                } else {
                    assertLe(
                        currentInvariant,
                        invariantWithDelta,
                        "Current invariant should be less than or equal to invariant with delta"
                    );
                }
            } catch {}
        } catch {}
    }
}
