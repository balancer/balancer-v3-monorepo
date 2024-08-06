// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { StableMath } from "../math/StableMath.sol";
import { FixedPoint } from "../math/FixedPoint.sol";
import { RoundingMock } from "./RoundingMock.sol";

/**
 * @dev This contract mocks the `StableMath` library for testing purposes. Its mock functions are meant to be
 * logically equivalent to the base ones (effectively copying them), but with the ability to test all permutations
 * of the rounding directions using the `RoundingMock` library.
 */
contract StableMathMock {
    using FixedPoint for uint256;
    using RoundingMock for uint256;

    function computeInvariant(
        uint256 amplificationParameter,
        uint256[] memory balances
    ) external pure returns (uint256) {
        return StableMath.computeInvariant(amplificationParameter, balances);
    }

    function computeOutGivenExactIn(
        uint256 amplificationParameter,
        uint256[] memory balances,
        uint256 tokenIndexIn,
        uint256 tokenIndexOut,
        uint256 tokenAmountIn,
        uint256 invariant
    ) external pure returns (uint256) {
        return
            StableMath.computeOutGivenExactIn(
                amplificationParameter,
                balances,
                tokenIndexIn,
                tokenIndexOut,
                tokenAmountIn,
                invariant
            );
    }

    function computeInGivenExactOut(
        uint256 amplificationParameter,
        uint256[] memory balances,
        uint256 tokenIndexIn,
        uint256 tokenIndexOut,
        uint256 tokenAmountOut,
        uint256 invariant
    ) external pure returns (uint256) {
        return
            StableMath.computeInGivenExactOut(
                amplificationParameter,
                balances,
                tokenIndexIn,
                tokenIndexOut,
                tokenAmountOut,
                invariant
            );
    }

    function computeBalance(
        uint256 amplificationParameter,
        uint256[] memory balances,
        uint256 invariant,
        uint256 tokenIndex
    ) external pure returns (uint256) {
        return StableMath.computeBalance(amplificationParameter, balances, invariant, tokenIndex);
    }

    function mockComputeOutGivenExactIn(
        uint256 amplificationParameter,
        uint256[] memory balances,
        uint256 tokenIndexIn,
        uint256 tokenIndexOut,
        uint256 tokenAmountIn,
        uint256 invariant
    ) external pure returns (uint256) {
        bool[3] memory roundingPermutationBase = [true, true, true];

        return
            _mockComputeOutGivenExactIn(
                amplificationParameter,
                balances,
                tokenIndexIn,
                tokenIndexOut,
                tokenAmountIn,
                invariant,
                roundingPermutationBase
            );
    }

    function mockComputeOutGivenExactIn(
        uint256 amplificationParameter,
        uint256[] memory balances,
        uint256 tokenIndexIn,
        uint256 tokenIndexOut,
        uint256 tokenAmountIn,
        uint256 invariant,
        bool[3] memory roundingPermutation
    ) external pure returns (uint256) {
        return
            _mockComputeOutGivenExactIn(
                amplificationParameter,
                balances,
                tokenIndexIn,
                tokenIndexOut,
                tokenAmountIn,
                invariant,
                roundingPermutation
            );
    }

    function mockComputeInGivenExactOut(
        uint256 amplificationParameter,
        uint256[] memory balances,
        uint256 tokenIndexIn,
        uint256 tokenIndexOut,
        uint256 tokenAmountOut,
        uint256 invariant
    ) external pure returns (uint256) {
        bool[3] memory roundingPermutationBase = [true, true, true];

        return
            _mockComputeInGivenExactOut(
                amplificationParameter,
                balances,
                tokenIndexIn,
                tokenIndexOut,
                tokenAmountOut,
                invariant,
                roundingPermutationBase
            );
    }

    function mockComputeInGivenExactOut(
        uint256 amplificationParameter,
        uint256[] memory balances,
        uint256 tokenIndexIn,
        uint256 tokenIndexOut,
        uint256 tokenAmountOut,
        uint256 invariant,
        bool[3] memory roundingPermutation
    ) external pure returns (uint256) {
        return
            _mockComputeInGivenExactOut(
                amplificationParameter,
                balances,
                tokenIndexIn,
                tokenIndexOut,
                tokenAmountOut,
                invariant,
                roundingPermutation
            );
    }

    function mockComputeBalance(
        uint256 amplificationParameter,
        uint256[] memory balances,
        uint256 invariant,
        uint256 tokenIndex
    ) external pure returns (uint256) {
        bool[3] memory roundingPermutationBase = [true, true, true];

        return _mockComputeBalance(amplificationParameter, balances, invariant, tokenIndex, roundingPermutationBase);
    }

    function mockComputeBalance(
        uint256 amplificationParameter,
        uint256[] memory balances,
        uint256 invariant,
        uint256 tokenIndex,
        bool[3] memory roundingPermutation
    ) external pure returns (uint256) {
        return _mockComputeBalance(amplificationParameter, balances, invariant, tokenIndex, roundingPermutation);
    }

    function _mockComputeOutGivenExactIn(
        uint256 amplificationParameter,
        uint256[] memory balances,
        uint256 tokenIndexIn,
        uint256 tokenIndexOut,
        uint256 tokenAmountIn,
        uint256 invariant,
        bool[3] memory roundingPermutation
    ) internal pure returns (uint256) {
        balances[tokenIndexIn] += tokenAmountIn;

        uint256 finalBalanceOut = _mockComputeBalance(
            amplificationParameter,
            balances,
            invariant,
            tokenIndexOut,
            roundingPermutation
        );

        balances[tokenIndexIn] -= tokenAmountIn;

        return balances[tokenIndexOut] - finalBalanceOut - 1;
    }

    function _mockComputeInGivenExactOut(
        uint256 amplificationParameter,
        uint256[] memory balances,
        uint256 tokenIndexIn,
        uint256 tokenIndexOut,
        uint256 tokenAmountOut,
        uint256 invariant,
        bool[3] memory roundingPermutation
    ) internal pure returns (uint256) {
        balances[tokenIndexOut] -= tokenAmountOut;

        uint256 finalBalanceIn = _mockComputeBalance(
            amplificationParameter,
            balances,
            invariant,
            tokenIndexIn,
            roundingPermutation
        );

        balances[tokenIndexOut] += tokenAmountOut;

        return finalBalanceIn - balances[tokenIndexIn] + 1;
    }

    function _mockComputeBalance(
        uint256 amplificationParameter,
        uint256[] memory balances,
        uint256 invariant,
        uint256 tokenIndex,
        bool[3] memory roundingPermutation
    ) internal pure returns (uint256) {
        uint256 numTokens = balances.length;
        uint256 ampTimesTotal = amplificationParameter * numTokens;
        uint256 sum = balances[0];
        uint256 P_D = balances[0] * numTokens;
        for (uint256 j = 1; j < numTokens; ++j) {
            P_D = (P_D * balances[j] * numTokens) / invariant;
            sum = sum + balances[j];
        }
        sum = sum - balances[tokenIndex];

        uint256 inv2 = invariant * invariant;
        uint256 c = (inv2 * StableMath.AMP_PRECISION).mockDivRaw(ampTimesTotal * P_D, roundingPermutation[0]) *
            balances[tokenIndex];
        uint256 b = sum + ((invariant / ampTimesTotal) * StableMath.AMP_PRECISION);
        uint256 prevTokenBalance = 0;
        uint256 tokenBalance = (inv2 + c).mockDivRaw(invariant + b, roundingPermutation[1]);

        for (uint256 i = 0; i < 255; ++i) {
            prevTokenBalance = tokenBalance;

            tokenBalance = ((tokenBalance * tokenBalance) + c).mockDivRaw(
                (tokenBalance * 2) + b - invariant,
                roundingPermutation[2]
            );

            if (tokenBalance > prevTokenBalance) {
                if (tokenBalance - prevTokenBalance <= 1) {
                    return tokenBalance;
                }
            } else if (prevTokenBalance - tokenBalance <= 1) {
                return tokenBalance;
            }
        }

        revert StableMath.StableGetBalanceDidNotConverge();
    }
}
