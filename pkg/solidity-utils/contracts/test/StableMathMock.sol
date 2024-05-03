// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { StableMath } from "../math/StableMath.sol";
import { FixedPoint } from "../math/FixedPoint.sol";

import { RoundingMock } from "./RoundingMock.sol";

// The `StableMathMock` contract mocks the `StableMath` library for testing purposes. Its mock functions are meant to be
// logically equivalent to the base ones, but with the ability to control the rounding permutation using the `RoundingMock`.

contract StableMathMock is RoundingMock {
    using FixedPoint for uint256;

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

    function computeBptOutGivenExactTokensIn(
        uint256 amp,
        uint256[] memory balances,
        uint256[] memory amountsIn,
        uint256 bptTotalSupply,
        uint256 currentInvariant,
        uint256 swapFeePercentage
    ) external pure returns (uint256) {
        return
            StableMath.computeBptOutGivenExactTokensIn(
                amp,
                balances,
                amountsIn,
                bptTotalSupply,
                currentInvariant,
                swapFeePercentage
            );
    }

    function computeTokenInGivenExactBptOut(
        uint256 amp,
        uint256[] memory balances,
        uint256 tokenIndex,
        uint256 bptAmountOut,
        uint256 bptTotalSupply,
        uint256 currentInvariant,
        uint256 swapFeePercentage
    ) external pure returns (uint256) {
        return
            StableMath.computeTokenInGivenExactBptOut(
                amp,
                balances,
                tokenIndex,
                bptAmountOut,
                bptTotalSupply,
                currentInvariant,
                swapFeePercentage
            );
    }

    function computeBptInGivenExactTokensOut(
        uint256 amp,
        uint256[] memory balances,
        uint256[] memory amountsOut,
        uint256 bptTotalSupply,
        uint256 currentInvariant,
        uint256 swapFeePercentage
    ) external pure returns (uint256) {
        return
            StableMath.computeBptInGivenExactTokensOut(
                amp,
                balances,
                amountsOut,
                bptTotalSupply,
                currentInvariant,
                swapFeePercentage
            );
    }

    function computeTokenOutGivenExactBptIn(
        uint256 amp,
        uint256[] memory balances,
        uint256 tokenIndex,
        uint256 bptAmountIn,
        uint256 bptTotalSupply,
        uint256 currentInvariant,
        uint256 swapFeePercentage
    ) external pure returns (uint256) {
        return
            StableMath.computeTokenOutGivenExactBptIn(
                amp,
                balances,
                tokenIndex,
                bptAmountIn,
                bptTotalSupply,
                currentInvariant,
                swapFeePercentage
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

    function mockComputeInvariant(
        uint256 amplificationParameter,
        uint256[] memory balances
    ) external pure returns (uint256) {
        return _mockComputeInvariant(amplificationParameter, balances);
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

    function mockComputeBptOutGivenExactTokensIn(
        uint256 amp,
        uint256[] memory balances,
        uint256[] memory amountsIn,
        uint256 bptTotalSupply,
        uint256 currentInvariant,
        uint256 swapFeePercentage
    ) external pure returns (uint256) {
        bool[7] memory roundingPermutationBase = [false, false, false, false, false, false, false];

        return
            _mockComputeBptOutGivenExactTokensIn(
                amp,
                balances,
                amountsIn,
                bptTotalSupply,
                currentInvariant,
                swapFeePercentage,
                roundingPermutationBase
            );
    }

    function mockComputeBptOutGivenExactTokensIn(
        uint256 amp,
        uint256[] memory balances,
        uint256[] memory amountsIn,
        uint256 bptTotalSupply,
        uint256 currentInvariant,
        uint256 swapFeePercentage,
        bool[7] memory roundingPermutation
    ) external pure returns (uint256) {
        return
            _mockComputeBptOutGivenExactTokensIn(
                amp,
                balances,
                amountsIn,
                bptTotalSupply,
                currentInvariant,
                swapFeePercentage,
                roundingPermutation
            );
    }

    function mockComputeTokenInGivenExactBptOut(
        uint256 amp,
        uint256[] memory balances,
        uint256 tokenIndex,
        uint256 bptAmountOut,
        uint256 bptTotalSupply,
        uint256 currentInvariant,
        uint256 swapFeePercentage
    ) external pure returns (uint256) {
        bool[8] memory roundingPermutationBase = [true, true, true, true, true, true, false, true];

        return
            _mockComputeTokenInGivenExactBptOut(
                amp,
                balances,
                tokenIndex,
                bptAmountOut,
                bptTotalSupply,
                currentInvariant,
                swapFeePercentage,
                roundingPermutationBase
            );
    }

    function mockComputeTokenInGivenExactBptOut(
        uint256 amp,
        uint256[] memory balances,
        uint256 tokenIndex,
        uint256 bptAmountOut,
        uint256 bptTotalSupply,
        uint256 currentInvariant,
        uint256 swapFeePercentage,
        bool[8] memory roundingPermutation
    ) external pure returns (uint256) {
        return
            _mockComputeTokenInGivenExactBptOut(
                amp,
                balances,
                tokenIndex,
                bptAmountOut,
                bptTotalSupply,
                currentInvariant,
                swapFeePercentage,
                roundingPermutation
            );
    }

    function mockComputeBptInGivenExactTokensOut(
        uint256 amp,
        uint256[] memory balances,
        uint256[] memory amountsOut,
        uint256 bptTotalSupply,
        uint256 currentInvariant,
        uint256 swapFeePercentage
    ) external pure returns (uint256) {
        bool[7] memory roundingPermutationBase = [false, false, false, true, true, false, true];

        return
            _mockComputeBptInGivenExactTokensOut(
                amp,
                balances,
                amountsOut,
                bptTotalSupply,
                currentInvariant,
                swapFeePercentage,
                roundingPermutationBase
            );
    }

    function mockComputeBptInGivenExactTokensOut(
        uint256 amp,
        uint256[] memory balances,
        uint256[] memory amountsOut,
        uint256 bptTotalSupply,
        uint256 currentInvariant,
        uint256 swapFeePercentage,
        bool[7] memory roundingPermutation
    ) external pure returns (uint256) {
        return
            _mockComputeBptInGivenExactTokensOut(
                amp,
                balances,
                amountsOut,
                bptTotalSupply,
                currentInvariant,
                swapFeePercentage,
                roundingPermutation
            );
    }

    function mockComputeTokenOutGivenExactBptIn(
        uint256 amp,
        uint256[] memory balances,
        uint256 tokenIndex,
        uint256 bptAmountIn,
        uint256 bptTotalSupply,
        uint256 currentInvariant,
        uint256 swapFeePercentage
    ) external pure returns (uint256) {
        bool[8] memory roundingPermutationBase = [true, true, true, true, true, false, true, false];

        return
            _mockComputeTokenOutGivenExactBptIn(
                amp,
                balances,
                tokenIndex,
                bptAmountIn,
                bptTotalSupply,
                currentInvariant,
                swapFeePercentage,
                roundingPermutationBase
            );
    }

    function mockComputeTokenOutGivenExactBptIn(
        uint256 amp,
        uint256[] memory balances,
        uint256 tokenIndex,
        uint256 bptAmountIn,
        uint256 bptTotalSupply,
        uint256 currentInvariant,
        uint256 swapFeePercentage,
        bool[8] memory roundingPermutation
    ) external pure returns (uint256) {
        return
            _mockComputeTokenOutGivenExactBptIn(
                amp,
                balances,
                tokenIndex,
                bptAmountIn,
                bptTotalSupply,
                currentInvariant,
                swapFeePercentage,
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

    function _mockComputeInvariant(
        uint256 amplificationParameter,
        uint256[] memory balances
    ) internal pure returns (uint256) {
        uint256 sum = 0;
        uint256 numTokens = balances.length;
        for (uint256 i = 0; i < numTokens; ++i) {
            sum = sum + balances[i];
        }
        if (sum == 0) {
            return 0;
        }

        uint256 prevInvariant;
        uint256 invariant = sum;
        uint256 ampTimesTotal = amplificationParameter * numTokens;

        for (uint256 i = 0; i < 255; ++i) {
            uint256 D_P = invariant;
            for (uint256 j = 0; j < numTokens; ++j) {
                D_P = (D_P * invariant) / (balances[j] * numTokens);
            }

            prevInvariant = invariant;

            invariant =
                ((((ampTimesTotal * sum) / StableMath.AMP_PRECISION) + (D_P * numTokens)) * invariant) /
                ((((ampTimesTotal - StableMath.AMP_PRECISION) * invariant) / StableMath.AMP_PRECISION) +
                    ((numTokens + 1) * D_P));

            if (invariant > prevInvariant) {
                if (invariant - prevInvariant <= 1) {
                    return invariant;
                }
            } else if (prevInvariant - invariant <= 1) {
                return invariant;
            }
        }

        revert StableMath.StableInvariantDidntConverge();
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

    function _mockComputeBptOutGivenExactTokensIn(
        uint256 amp,
        uint256[] memory balances,
        uint256[] memory amountsIn,
        uint256 bptTotalSupply,
        uint256 currentInvariant,
        uint256 swapFeePercentage,
        bool[7] memory roundingPermutation
    ) internal pure returns (uint256) {
        uint256 sumBalances = 0;
        uint256 numTokens = balances.length;
        for (uint256 i = 0; i < numTokens; ++i) {
            sumBalances += balances[i];
        }

        uint256[] memory balanceRatiosWithFee = new uint256[](numTokens);
        uint256 invariantRatioWithFees = 0;
        for (uint256 i = 0; i < numTokens; ++i) {
            uint256 currentWeight = mockDiv(balances[i], sumBalances, roundingPermutation[0]);
            balanceRatiosWithFee[i] = mockDiv(balances[i] + amountsIn[i], balances[i], roundingPermutation[1]);
            invariantRatioWithFees += mockMul(balanceRatiosWithFee[i], currentWeight, roundingPermutation[2]);
        }

        uint256[] memory newBalances = new uint256[](numTokens);
        for (uint256 i = 0; i < numTokens; ++i) {
            uint256 amountInWithoutFee;

            if (balanceRatiosWithFee[i] > invariantRatioWithFees) {
                uint256 nonTaxableAmount = mockMul(
                    balances[i],
                    invariantRatioWithFees - FixedPoint.ONE,
                    roundingPermutation[3]
                );
                uint256 taxableAmount = amountsIn[i] - nonTaxableAmount;
                amountInWithoutFee =
                    nonTaxableAmount +
                    mockMul(taxableAmount, FixedPoint.ONE - swapFeePercentage, roundingPermutation[4]);
            } else {
                amountInWithoutFee = amountsIn[i];
            }

            newBalances[i] = balances[i] + amountInWithoutFee;
        }

        uint256 newInvariant = _mockComputeInvariant(amp, newBalances);
        uint256 invariantRatio = mockDiv(newInvariant, currentInvariant, roundingPermutation[5]);

        if (invariantRatio > FixedPoint.ONE) {
            return mockMul(bptTotalSupply, invariantRatio - FixedPoint.ONE, roundingPermutation[6]);
        } else {
            return 0;
        }
    }

    function _mockComputeTokenInGivenExactBptOut(
        uint256 amp,
        uint256[] memory balances,
        uint256 tokenIndex,
        uint256 bptAmountOut,
        uint256 bptTotalSupply,
        uint256 currentInvariant,
        uint256 swapFeePercentage,
        bool[8] memory roundingPermutation
    ) internal pure returns (uint256) {
        uint256 newInvariant = mockMul(
            mockDiv(bptTotalSupply + bptAmountOut, bptTotalSupply, roundingPermutation[0]),
            currentInvariant,
            roundingPermutation[1]
        );

        bool[3] memory subRoundingPermutation = [
            roundingPermutation[2],
            roundingPermutation[3],
            roundingPermutation[4]
        ];
        uint256 newBalanceTokenIndex = _mockComputeBalance(
            amp,
            balances,
            newInvariant,
            tokenIndex,
            subRoundingPermutation
        );
        uint256 amountInWithoutFee = newBalanceTokenIndex - balances[tokenIndex];

        uint256 sumBalances = 0;
        for (uint256 i = 0; i < balances.length; ++i) {
            sumBalances += balances[i];
        }

        uint256 currentWeight = mockDiv(balances[tokenIndex], sumBalances, roundingPermutation[5]);
        uint256 taxablePercentage = currentWeight.complement();
        uint256 taxableAmount = mockMul(amountInWithoutFee, taxablePercentage, roundingPermutation[6]);
        uint256 nonTaxableAmount = amountInWithoutFee - taxableAmount;

        return nonTaxableAmount + mockDiv(taxableAmount, FixedPoint.ONE - swapFeePercentage, roundingPermutation[7]);
    }

    function _mockComputeBptInGivenExactTokensOut(
        uint256 amp,
        uint256[] memory balances,
        uint256[] memory amountsOut,
        uint256 bptTotalSupply,
        uint256 currentInvariant,
        uint256 swapFeePercentage,
        bool[7] memory roundingPermutation
    ) internal pure returns (uint256) {
        uint256 sumBalances = 0;
        uint256 numTokens = balances.length;
        for (uint256 i = 0; i < numTokens; ++i) {
            sumBalances += balances[i];
        }

        uint256[] memory balanceRatiosWithoutFee = new uint256[](numTokens);
        uint256 invariantRatioWithoutFees = 0;
        for (uint256 i = 0; i < numTokens; ++i) {
            uint256 currentWeight = mockDiv(balances[i], sumBalances, roundingPermutation[0]);
            balanceRatiosWithoutFee[i] = mockDiv(balances[i] - amountsOut[i], balances[i], roundingPermutation[1]);
            invariantRatioWithoutFees += mockMul(balanceRatiosWithoutFee[i], currentWeight, roundingPermutation[2]);
        }

        uint256[] memory newBalances = new uint256[](numTokens);
        for (uint256 i = 0; i < numTokens; ++i) {
            uint256 amountOutWithFee;
            if (invariantRatioWithoutFees > balanceRatiosWithoutFee[i]) {
                uint256 nonTaxableAmount = mockMul(
                    balances[i],
                    invariantRatioWithoutFees.complement(),
                    roundingPermutation[3]
                );
                uint256 taxableAmount = amountsOut[i] - nonTaxableAmount;
                amountOutWithFee =
                    nonTaxableAmount +
                    mockDiv(taxableAmount, FixedPoint.ONE - swapFeePercentage, roundingPermutation[4]);
            } else {
                amountOutWithFee = amountsOut[i];
            }

            newBalances[i] = balances[i] - amountOutWithFee;
        }

        uint256 newInvariant = _mockComputeInvariant(amp, newBalances);
        uint256 invariantRatio = mockDiv(newInvariant, currentInvariant, roundingPermutation[5]);

        return mockMul(bptTotalSupply, invariantRatio.complement(), roundingPermutation[6]);
    }

    function _mockComputeTokenOutGivenExactBptIn(
        uint256 amp,
        uint256[] memory balances,
        uint256 tokenIndex,
        uint256 bptAmountIn,
        uint256 bptTotalSupply,
        uint256 currentInvariant,
        uint256 swapFeePercentage,
        bool[8] memory roundingPermutation
    ) internal pure returns (uint256) {
        uint256 newInvariant = mockMul(
            mockDiv(bptTotalSupply - bptAmountIn, bptTotalSupply, roundingPermutation[0]),
            currentInvariant,
            roundingPermutation[1]
        );

        bool[3] memory subRoundingPermutation = [
            roundingPermutation[2],
            roundingPermutation[3],
            roundingPermutation[4]
        ];
        uint256 newBalanceTokenIndex = _mockComputeBalance(
            amp,
            balances,
            newInvariant,
            tokenIndex,
            subRoundingPermutation
        );
        uint256 amountOutWithoutFee = balances[tokenIndex] - newBalanceTokenIndex;

        uint256 sumBalances = 0;
        for (uint256 i = 0; i < balances.length; ++i) {
            sumBalances += balances[i];
        }

        uint256 currentWeight = mockDiv(balances[tokenIndex], sumBalances, roundingPermutation[5]);
        uint256 taxablePercentage = currentWeight.complement();
        uint256 taxableAmount = mockMul(amountOutWithoutFee, taxablePercentage, roundingPermutation[6]);
        uint256 nonTaxableAmount = amountOutWithoutFee - taxableAmount;

        return nonTaxableAmount + mockMul(taxableAmount, FixedPoint.ONE - swapFeePercentage, roundingPermutation[7]);
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
        uint256 c = (mockDivRaw(inv2, ampTimesTotal * P_D, roundingPermutation[0]) * StableMath.AMP_PRECISION) *
            balances[tokenIndex];
        uint256 b = sum + ((invariant / ampTimesTotal) * StableMath.AMP_PRECISION);
        uint256 prevTokenBalance = 0;
        uint256 tokenBalance = mockDivRaw(inv2 + c, invariant + b, roundingPermutation[1]);

        for (uint256 i = 0; i < 255; ++i) {
            prevTokenBalance = tokenBalance;

            tokenBalance = mockDivRaw(
                (tokenBalance * tokenBalance) + c,
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

        revert StableMath.StableGetBalanceDidntConverge();
    }
}
