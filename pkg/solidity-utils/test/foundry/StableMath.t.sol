// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { StableMath } from "../../contracts/math/StableMath.sol";
import { FixedPoint } from "../../contracts/math/FixedPoint.sol";
import { StableMathMock } from "../../contracts/test/StableMathMock.sol";

// In the `StableMath` functions, the protocol aims for computing a value either as small as possible or as large as possible
// by means of rounding in its favor; in order to achieve this, it may use arbitrary rounding directions during the calculations.
// The objective of `StableMathTest` is to verify that the implemented rounding permutations favor the protocol more than other
// solutions (e.g., always rounding down or always rounding up).

contract StableMathTest is Test {
    using FixedPoint for uint256;

    uint256 constant NUM_TOKENS = 4;

    uint256 constant MIN_BALANCE_BASE = 1e18;
    // Max balance of a stable pool token that won't cause an overflow in stable math.
    uint256 constant MAX_BALANCE_BASE = 10_000_000_000_000_000e18;
    uint256 constant MAX_BALANCE_RATIO = 1000e16; // 1000 %

    uint256 constant MIN_AMOUNT_RATIO = 0.01e16; // 0.01 %
    uint256 constant MAX_AMOUNT_RATIO = 99.99e16; // 99.99 %

    uint256 constant MIN_AMP = StableMath.MIN_AMP * StableMath.AMP_PRECISION;
    uint256 constant MAX_AMP = StableMath.MAX_AMP * StableMath.AMP_PRECISION;

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

        stableMathMock.computeInvariant(amp, balances);
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
        uint256 invariant = stableMathMock.computeInvariant(amp, balances);

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
        uint256 invariant = stableMathMock.computeInvariant(amp, balances);

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
        uint256 invariant = stableMathMock.computeInvariant(amp, balances);
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
}
