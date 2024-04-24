// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { FixedPoint } from "../../contracts/math/FixedPoint.sol";

import { StableMathMock } from "../../contracts/test/StableMathMock.sol";
import { RoundingMock } from "../../contracts/test/RoundingMock.sol";

contract StableMathTest is Test {
    uint256 constant NUM_TOKENS = 2;

    uint256 constant MIN_BALANCE = 1e18;
    uint256 constant MAX_BALANCE = 1000e18;

    uint256 constant MIN_IN_RATIO = 0.01e16; // 0.01 %
    uint256 constant MAX_IN_RATIO = 3e16; // 3 %
    uint256 constant MIN_OUT_RATIO = 0.01e16; // 0.01 %
    uint256 constant MAX_OUT_RATIO = 3e16; // 3 %

    uint256 constant MIN_INVARIANT_IN = 1e12;
    uint256 constant MAX_INVARIANT_IN = 1e18;
    uint256 constant MIN_INVARIANT_OUT = 1e22;
    uint256 constant MAX_INVARIANT_OUT = 1e28;

    uint256 constant MIN_AMP = 3500;
    uint256 constant MAX_AMP = 5000;

    uint256 constant MIN_SWAP_FEE = 0; // 0 %
    uint256 constant MAX_SWAP_FEE = 10e16; // 10 %

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
        tokenIndexIn = rawTokenIndexIn % NUM_TOKENS;
        tokenIndexOut = rawTokenIndexOut % NUM_TOKENS;
        vm.assume(tokenIndexIn != tokenIndexOut);
    }

    function boundBalance(uint256 rawBalance) internal pure returns (uint256 balance) {
        balance = bound(rawBalance, MIN_BALANCE, MAX_BALANCE);
    }

    function boundBalances(uint256[NUM_TOKENS] calldata rawBalances) internal pure returns (uint256[] memory balances) {
        balances = new uint256[](NUM_TOKENS);
        for (uint256 i = 0; i < NUM_TOKENS; ++i) {
            balances[i] = boundBalance(rawBalances[i]);
        }
    }

    function boundAmountIn(uint256 rawAmountIn, uint256 balanceIn) internal pure returns (uint256 amountIn) {
        amountIn = bound(
            rawAmountIn,
            FixedPoint.mulDown(balanceIn, MIN_IN_RATIO),
            FixedPoint.mulDown(balanceIn, MAX_IN_RATIO)
        );
    }

    function boundAmountsIn(
        uint256[NUM_TOKENS] calldata rawAmountsIn,
        uint256[] memory balances
    ) internal pure returns (uint256[] memory amountsIn) {
        amountsIn = new uint256[](NUM_TOKENS);
        for (uint256 i = 0; i < NUM_TOKENS; ++i) {
            amountsIn[i] = boundAmountIn(rawAmountsIn[i], balances[i]);
        }
    }

    function boundAmountOut(uint256 rawAmountOut, uint256 balanceOut) internal pure returns (uint256 amountOut) {
        amountOut = bound(
            rawAmountOut,
            FixedPoint.mulDown(balanceOut, MIN_OUT_RATIO),
            FixedPoint.mulDown(balanceOut, MAX_OUT_RATIO)
        );
    }

    function boundAmountsOut(
        uint256[NUM_TOKENS] calldata rawAmountsOut,
        uint256[] memory balances
    ) internal pure returns (uint256[] memory amountsOut) {
        amountsOut = new uint256[](NUM_TOKENS);
        for (uint256 i = 0; i < NUM_TOKENS; ++i) {
            amountsOut[i] = boundAmountOut(rawAmountsOut[i], balances[i]);
        }
    }

    function boundInvariantIn(uint256 rawInvariantIn) internal pure returns (uint256 invariantIn) {
        invariantIn = bound(rawInvariantIn, MIN_INVARIANT_IN, MAX_INVARIANT_IN);
    }

    function boundInvariantOut(uint256 rawInvariantOut) internal pure returns (uint256 invariantOut) {
        invariantOut = bound(rawInvariantOut, MIN_INVARIANT_OUT, MAX_INVARIANT_OUT);
    }

    function boundAmp(uint256 rawAmp) internal pure returns (uint256 amp) {
        amp = bound(rawAmp, MIN_AMP, MAX_AMP);
    }

    function boundSwapFeePercentage(uint256 rawSwapFeePercentage) internal pure returns (uint256 swapFeePercentage) {
        swapFeePercentage = bound(rawSwapFeePercentage, MIN_SWAP_FEE, MAX_SWAP_FEE);
    }

    function testComputeInvariantRounding__Fuzz(uint256 rawAmp, uint256[NUM_TOKENS] calldata rawBalances) external {
        uint256 amp = boundAmp(rawAmp);
        uint256[] memory balances = boundBalances(rawBalances);

        uint256 invariant = stableMathMock.computeInvariant(amp, balances);

        stableMathMock.setMockRounding(RoundingMock.MockRounding.Disabled);
        uint256 invariantUnrounded = stableMathMock.mockComputeInvariant(amp, balances);

        stableMathMock.setMockRounding(RoundingMock.MockRounding.RoundDown);
        uint256 invariantRoundedDown = stableMathMock.mockComputeInvariant(amp, balances);

        stableMathMock.setMockRounding(RoundingMock.MockRounding.RoundUp);
        uint256 invariantRoundedUp = stableMathMock.mockComputeInvariant(amp, balances);

        assertEq(invariant, invariantUnrounded, "Mock function and base one should be equivalent.");
        assertLe(
            invariant,
            invariantRoundedDown,
            "Output should be less than or equal to the rounded down mock value."
        );
        assertLe(invariant, invariantRoundedUp, "Output should be less than or equal to the rounded up mock value.");
    }

    function testComputeOutGivenExactInRounding__Fuzz(
        uint256 rawAmp,
        uint256[NUM_TOKENS] calldata rawBalances,
        uint256 rawTokenIndexIn,
        uint256 rawTokenIndexOut,
        uint256 rawTokenAmountIn,
        uint256 rawInvariant
    ) external {
        uint256 amp = boundAmp(rawAmp);
        uint256[] memory balances = boundBalances(rawBalances);
        (uint256 tokenIndexIn, uint256 tokenIndexOut) = boundTokenIndexes(rawTokenIndexIn, rawTokenIndexOut);
        uint256 tokenAmountIn = boundAmountIn(rawTokenAmountIn, balances[tokenIndexIn]);
        uint256 invariant = boundInvariantIn(rawInvariant);

        uint256 outGivenExactIn = stableMathMock.computeOutGivenExactIn(
            amp,
            balances,
            tokenIndexIn,
            tokenIndexOut,
            tokenAmountIn,
            invariant
        );

        stableMathMock.setMockRounding(RoundingMock.MockRounding.Disabled);
        uint256 outGivenExactInUnrounded = stableMathMock.mockComputeOutGivenExactIn(
            amp,
            balances,
            tokenIndexIn,
            tokenIndexOut,
            tokenAmountIn,
            invariant
        );

        stableMathMock.setMockRounding(RoundingMock.MockRounding.RoundDown);
        uint256 outGivenExactInRoundedDown = stableMathMock.mockComputeOutGivenExactIn(
            amp,
            balances,
            tokenIndexIn,
            tokenIndexOut,
            tokenAmountIn,
            invariant
        );

        stableMathMock.setMockRounding(RoundingMock.MockRounding.RoundUp);
        uint256 outGivenExactInRoundedUp = stableMathMock.mockComputeOutGivenExactIn(
            amp,
            balances,
            tokenIndexIn,
            tokenIndexOut,
            tokenAmountIn,
            invariant
        );

        assertEq(outGivenExactIn, outGivenExactInUnrounded, "Mock function and base one should be equivalent.");
        assertLe(
            outGivenExactIn,
            outGivenExactInRoundedDown,
            "Output should be less than or equal to the rounded down mock value."
        );
        assertLe(
            outGivenExactIn,
            outGivenExactInRoundedUp,
            "Output should be less than or equal to the rounded up mock value."
        );
    }

    function testComputeInGivenExactOutRounding__Fuzz(
        uint256 rawAmp,
        uint256[NUM_TOKENS] calldata rawBalances,
        uint256 rawTokenIndexIn,
        uint256 rawTokenIndexOut,
        uint256 rawTokenAmountOut,
        uint256 rawInvariant
    ) external {
        uint256 amp = boundAmp(rawAmp);
        uint256[] memory balances = boundBalances(rawBalances);
        (uint256 tokenIndexIn, uint256 tokenIndexOut) = boundTokenIndexes(rawTokenIndexIn, rawTokenIndexOut);
        uint256 tokenAmountOut = boundAmountOut(rawTokenAmountOut, balances[tokenIndexOut]);
        uint256 invariant = boundInvariantOut(rawInvariant);

        uint256 inGivenExactOut = stableMathMock.computeInGivenExactOut(
            amp,
            balances,
            tokenIndexIn,
            tokenIndexOut,
            tokenAmountOut,
            invariant
        );

        stableMathMock.setMockRounding(RoundingMock.MockRounding.Disabled);
        uint256 inGivenExactOutUnrounded = stableMathMock.mockComputeInGivenExactOut(
            amp,
            balances,
            tokenIndexIn,
            tokenIndexOut,
            tokenAmountOut,
            invariant
        );

        stableMathMock.setMockRounding(RoundingMock.MockRounding.RoundDown);
        uint256 inGivenExactOutRoundedDown = stableMathMock.mockComputeInGivenExactOut(
            amp,
            balances,
            tokenIndexIn,
            tokenIndexOut,
            tokenAmountOut,
            invariant
        );

        stableMathMock.setMockRounding(RoundingMock.MockRounding.RoundUp);
        uint256 inGivenExactOutRoundedUp = stableMathMock.mockComputeInGivenExactOut(
            amp,
            balances,
            tokenIndexIn,
            tokenIndexOut,
            tokenAmountOut,
            invariant
        );

        assertEq(inGivenExactOut, inGivenExactOutUnrounded, "Mock function and base one should be equivalent.");
        assertGe(
            inGivenExactOut,
            inGivenExactOutRoundedDown,
            "Output should be greater than or equal to the rounded down mock value."
        );
        assertGe(
            inGivenExactOut,
            inGivenExactOutRoundedUp,
            "Output should be greater than or equal to the rounded up mock value."
        );
    }

    function testComputeBptOutGivenExactTokensInRounding__Fuzz(
        uint256 rawAmp,
        uint256[NUM_TOKENS] calldata rawBalances,
        uint256[NUM_TOKENS] calldata rawAmountsIn,
        uint256 rawBptTotalSupply,
        uint256 rawCurrentInvariant,
        uint256 rawSwapFeePercentage
    ) external {
        uint256 amp = boundAmp(rawAmp);
        uint256[] memory balances = boundBalances(rawBalances);
        uint256[] memory amountsIn = boundAmountsIn(rawAmountsIn, balances);
        uint256 bptTotalSupply = boundBalance(rawBptTotalSupply);
        uint256 currentInvariant = boundInvariantIn(rawCurrentInvariant);
        uint256 swapFeePercentage = boundSwapFeePercentage(rawSwapFeePercentage);

        uint256 bptOutGivenExactTokensIn = stableMathMock.computeBptOutGivenExactTokensIn(
            amp,
            balances,
            amountsIn,
            bptTotalSupply,
            currentInvariant,
            swapFeePercentage
        );

        stableMathMock.setMockRounding(RoundingMock.MockRounding.Disabled);
        uint256 bptOutGivenExactTokensInUnrounded = stableMathMock.mockComputeBptOutGivenExactTokensIn(
            amp,
            balances,
            amountsIn,
            bptTotalSupply,
            currentInvariant,
            swapFeePercentage
        );

        stableMathMock.setMockRounding(RoundingMock.MockRounding.RoundDown);
        uint256 bptOutGivenExactTokensInRoundedDown = stableMathMock.mockComputeBptOutGivenExactTokensIn(
            amp,
            balances,
            amountsIn,
            bptTotalSupply,
            currentInvariant,
            swapFeePercentage
        );

        stableMathMock.setMockRounding(RoundingMock.MockRounding.RoundUp);
        uint256 bptOutGivenExactTokensInRoundedUp = stableMathMock.mockComputeBptOutGivenExactTokensIn(
            amp,
            balances,
            amountsIn,
            bptTotalSupply,
            currentInvariant,
            swapFeePercentage
        );

        assertEq(
            bptOutGivenExactTokensIn,
            bptOutGivenExactTokensInUnrounded,
            "Mock function and base one should be equivalent."
        );
        assertLe(
            bptOutGivenExactTokensIn,
            bptOutGivenExactTokensInRoundedDown,
            "Output should be less than or equal to the rounded down mock value."
        );
        // BUG: Revise rounding in `computeBptOutGivenExactTokensIn()`
        // assertLe(bptOutGivenExactTokensIn, bptOutGivenExactTokensInRoundedUp, "Output should be less than or equal to the rounded up mock value.");
    }

    function testComputeTokenInGivenExactBptOutRounding__Fuzz(
        uint256 rawAmp,
        uint256[NUM_TOKENS] calldata rawBalances,
        uint256 rawTokenIndex,
        uint256 rawBptAmountOut,
        uint256 rawBptTotalSupply,
        uint256 rawCurrentInvariant,
        uint256 rawSwapFeePercentage
    ) external {
        uint256 amp = boundAmp(rawAmp);
        uint256[] memory balances = boundBalances(rawBalances);
        uint256 tokenIndex = boundTokenIndex(rawTokenIndex);
        uint256 bptTotalSupply = boundBalance(rawBptTotalSupply);
        uint256 bptAmountOut = boundAmountOut(rawBptAmountOut, bptTotalSupply);
        uint256 currentInvariant = boundInvariantOut(rawCurrentInvariant);
        uint256 swapFeePercentage = boundSwapFeePercentage(rawSwapFeePercentage);

        uint256 tokenInGivenExactBptOut = stableMathMock.computeTokenInGivenExactBptOut(
            amp,
            balances,
            tokenIndex,
            bptAmountOut,
            bptTotalSupply,
            currentInvariant,
            swapFeePercentage
        );

        stableMathMock.setMockRounding(RoundingMock.MockRounding.Disabled);
        uint256 tokenInGivenExactBptOutUnrounded = stableMathMock.mockComputeTokenInGivenExactBptOut(
            amp,
            balances,
            tokenIndex,
            bptAmountOut,
            bptTotalSupply,
            currentInvariant,
            swapFeePercentage
        );

        stableMathMock.setMockRounding(RoundingMock.MockRounding.RoundDown);
        uint256 tokenInGivenExactBptOutRoundedDown = stableMathMock.mockComputeTokenInGivenExactBptOut(
            amp,
            balances,
            tokenIndex,
            bptAmountOut,
            bptTotalSupply,
            currentInvariant,
            swapFeePercentage
        );

        stableMathMock.setMockRounding(RoundingMock.MockRounding.RoundUp);
        uint256 tokenInGivenExactBptOutRoundedUp = stableMathMock.mockComputeTokenInGivenExactBptOut(
            amp,
            balances,
            tokenIndex,
            bptAmountOut,
            bptTotalSupply,
            currentInvariant,
            swapFeePercentage
        );

        assertEq(
            tokenInGivenExactBptOut,
            tokenInGivenExactBptOutUnrounded,
            "Mock function and base one should be equivalent."
        );
        // BUG: Revise rounding in `computeTokenInGivenExactBptOut()`
        // assertGe(tokenInGivenExactBptOut, tokenInGivenExactBptOutRoundedDown, "Output should be greater than or equal to the rounded down mock value.");
        // assertGe(tokenInGivenExactBptOut, tokenInGivenExactBptOutRoundedUp, "Output should be greater than or equal to the rounded up mock value.");
    }

    function testComputeBptInGivenExactTokensOutRounding__Fuzz(
        uint256 rawAmp,
        uint256[NUM_TOKENS] calldata rawBalances,
        uint256[NUM_TOKENS] calldata rawAmountsOut,
        uint256 rawBptTotalSupply,
        uint256 rawCurrentInvariant,
        uint256 rawSwapFeePercentage
    ) external {
        uint256 amp = boundAmp(rawAmp);
        uint256[] memory balances = boundBalances(rawBalances);
        uint256[] memory amountsOut = boundAmountsOut(rawAmountsOut, balances);
        uint256 bptTotalSupply = boundBalance(rawBptTotalSupply);
        uint256 currentInvariant = boundInvariantOut(rawCurrentInvariant);
        uint256 swapFeePercentage = boundSwapFeePercentage(rawSwapFeePercentage);

        uint256 bptInGivenExactTokensOut = stableMathMock.computeBptInGivenExactTokensOut(
            amp,
            balances,
            amountsOut,
            bptTotalSupply,
            currentInvariant,
            swapFeePercentage
        );

        stableMathMock.setMockRounding(RoundingMock.MockRounding.Disabled);
        uint256 bptInGivenExactTokensOutUnrounded = stableMathMock.mockComputeBptInGivenExactTokensOut(
            amp,
            balances,
            amountsOut,
            bptTotalSupply,
            currentInvariant,
            swapFeePercentage
        );

        stableMathMock.setMockRounding(RoundingMock.MockRounding.RoundDown);
        uint256 bptInGivenExactTokensOutRoundedDown = stableMathMock.mockComputeBptInGivenExactTokensOut(
            amp,
            balances,
            amountsOut,
            bptTotalSupply,
            currentInvariant,
            swapFeePercentage
        );

        stableMathMock.setMockRounding(RoundingMock.MockRounding.RoundUp);
        uint256 bptInGivenExactTokensOutRoundedUp = stableMathMock.mockComputeBptInGivenExactTokensOut(
            amp,
            balances,
            amountsOut,
            bptTotalSupply,
            currentInvariant,
            swapFeePercentage
        );

        assertEq(
            bptInGivenExactTokensOut,
            bptInGivenExactTokensOutUnrounded,
            "Mock function and base one should be equivalent."
        );
        // BUG: Revise rounding in `computeBptInGivenExactTokensOut()`
        // assertGe(bptInGivenExactTokensOut, bptInGivenExactTokensOutRoundedDown, "Output should be greater than or equal to the rounded down mock value.");
        // assertGe(bptInGivenExactTokensOut, bptInGivenExactTokensOutRoundedUp, "Output should be greater than or equal to the rounded up mock value.");
    }

    function testComputeTokenOutGivenExactBptInRounding__Fuzz(
        uint256 rawAmp,
        uint256[NUM_TOKENS] calldata rawBalances,
        uint256 rawTokenIndex,
        uint256 rawBptAmountIn,
        uint256 rawBptTotalSupply,
        uint256 rawCurrentInvariant,
        uint256 rawSwapFeePercentage
    ) external {
        uint256 amp = boundAmp(rawAmp);
        uint256[] memory balances = boundBalances(rawBalances);
        uint256 tokenIndex = boundTokenIndex(rawTokenIndex);
        uint256 bptTotalSupply = boundBalance(rawBptTotalSupply);
        uint256 bptAmountIn = boundAmountIn(rawBptAmountIn, bptTotalSupply);
        uint256 currentInvariant = boundInvariantIn(rawCurrentInvariant);
        uint256 swapFeePercentage = boundSwapFeePercentage(rawSwapFeePercentage);

        uint256 tokenOutGivenExactBptIn = stableMathMock.computeTokenOutGivenExactBptIn(
            amp,
            balances,
            tokenIndex,
            bptAmountIn,
            bptTotalSupply,
            currentInvariant,
            swapFeePercentage
        );

        stableMathMock.setMockRounding(RoundingMock.MockRounding.Disabled);
        uint256 tokenOutGivenExactBptInUnrounded = stableMathMock.mockComputeTokenOutGivenExactBptIn(
            amp,
            balances,
            tokenIndex,
            bptAmountIn,
            bptTotalSupply,
            currentInvariant,
            swapFeePercentage
        );

        stableMathMock.setMockRounding(RoundingMock.MockRounding.RoundDown);
        uint256 tokenOutGivenExactBptInRoundedDown = stableMathMock.mockComputeTokenOutGivenExactBptIn(
            amp,
            balances,
            tokenIndex,
            bptAmountIn,
            bptTotalSupply,
            currentInvariant,
            swapFeePercentage
        );

        stableMathMock.setMockRounding(RoundingMock.MockRounding.RoundUp);
        uint256 tokenOutGivenExactBptInRoundedUp = stableMathMock.mockComputeTokenOutGivenExactBptIn(
            amp,
            balances,
            tokenIndex,
            bptAmountIn,
            bptTotalSupply,
            currentInvariant,
            swapFeePercentage
        );

        assertEq(
            tokenOutGivenExactBptIn,
            tokenOutGivenExactBptInUnrounded,
            "Mock function and base one should be equivalent."
        );
        assertLe(
            tokenOutGivenExactBptIn,
            tokenOutGivenExactBptInRoundedDown,
            "Output should be less than or equal to the rounded down mock value."
        );
        assertLe(
            tokenOutGivenExactBptIn,
            tokenOutGivenExactBptInRoundedUp,
            "Output should be less than or equal to the rounded up mock value."
        );
    }

    function testComputeBalanceRounding__Fuzz(
        uint256 rawAmp,
        uint256[NUM_TOKENS] calldata rawBalances,
        uint256 rawInvariant,
        uint256 rawTokenIndex
    ) external {
        uint256 amp = boundAmp(rawAmp);
        uint256[] memory balances = boundBalances(rawBalances);
        uint256 invariant = boundInvariantOut(rawInvariant);
        uint256 tokenIndex = boundTokenIndex(rawTokenIndex);

        uint256 balance = stableMathMock.computeBalance(amp, balances, invariant, tokenIndex);

        stableMathMock.setMockRounding(RoundingMock.MockRounding.Disabled);
        uint256 balanceUnrounded = stableMathMock.mockComputeBalance(amp, balances, invariant, tokenIndex);

        stableMathMock.setMockRounding(RoundingMock.MockRounding.RoundDown);
        uint256 balanceRoundedDown = stableMathMock.mockComputeBalance(amp, balances, invariant, tokenIndex);

        stableMathMock.setMockRounding(RoundingMock.MockRounding.RoundUp);
        uint256 balanceRoundedUp = stableMathMock.mockComputeBalance(amp, balances, invariant, tokenIndex);

        assertEq(balance, balanceUnrounded, "Mock function and base one should be equivalent.");
        assertGe(balance, balanceRoundedDown, "Output should be greater than or equal to the rounded down mock value.");
        assertGe(balance, balanceRoundedUp, "Output should be greater than or equal to the rounded up mock value.");
    }
}
