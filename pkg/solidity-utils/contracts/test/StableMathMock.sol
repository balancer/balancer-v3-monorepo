// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { StableMath } from "../math/StableMath.sol";
import { FixedPoint } from "../math/FixedPoint.sol";

import { RoundingMock } from "./RoundingMock.sol";

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
    ) public pure returns (uint256) {
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

            unchecked {
                if (invariant > prevInvariant) {
                    if (invariant - prevInvariant <= 1) {
                        return invariant;
                    }
                } else if (prevInvariant - invariant <= 1) {
                    return invariant;
                }
            }
        }

        revert StableMath.StableInvariantDidntConverge();
    }

    function mockComputeOutGivenExactIn(
        uint256 amplificationParameter,
        uint256[] memory balances,
        uint256 tokenIndexIn,
        uint256 tokenIndexOut,
        uint256 tokenAmountIn,
        uint256 invariant
    ) external view returns (uint256) {
        balances[tokenIndexIn] += tokenAmountIn;

        uint256 finalBalanceOut = mockComputeBalance(amplificationParameter, balances, invariant, tokenIndexOut);

        unchecked {
            balances[tokenIndexIn] -= tokenAmountIn;
        }

        return balances[tokenIndexOut] - finalBalanceOut - 1;
    }

    function mockComputeInGivenExactOut(
        uint256 amplificationParameter,
        uint256[] memory balances,
        uint256 tokenIndexIn,
        uint256 tokenIndexOut,
        uint256 tokenAmountOut,
        uint256 invariant
    ) external view returns (uint256) {
        balances[tokenIndexOut] -= tokenAmountOut;

        uint256 finalBalanceIn = mockComputeBalance(amplificationParameter, balances, invariant, tokenIndexIn);

        unchecked {
            balances[tokenIndexOut] += tokenAmountOut;
        }

        return finalBalanceIn - balances[tokenIndexIn] + 1;
    }

    function mockComputeBptOutGivenExactTokensIn(
        uint256 amp,
        uint256[] memory balances,
        uint256[] memory amountsIn,
        uint256 bptTotalSupply,
        uint256 currentInvariant,
        uint256 swapFeePercentage
    ) external view returns (uint256) {
        uint256 sumBalances = 0;
        uint256 numTokens = balances.length;
        for (uint256 i = 0; i < numTokens; ++i) {
            sumBalances += balances[i];
        }

        uint256[] memory balanceRatiosWithFee = new uint256[](numTokens);
        uint256 invariantRatioWithFees = 0;
        for (uint256 i = 0; i < numTokens; ++i) {
            uint256 currentWeight = divDown(balances[i], sumBalances);
            balanceRatiosWithFee[i] = divDown(balances[i] + amountsIn[i], balances[i]);
            invariantRatioWithFees += mulDown(balanceRatiosWithFee[i], currentWeight);
        }

        uint256[] memory newBalances = new uint256[](numTokens);
        for (uint256 i = 0; i < numTokens; ++i) {
            uint256 amountInWithoutFee;

            if (balanceRatiosWithFee[i] > invariantRatioWithFees) {
                uint256 nonTaxableAmount = mulDown(balances[i], invariantRatioWithFees - FixedPoint.ONE);
                uint256 taxableAmount = amountsIn[i] - nonTaxableAmount;
                amountInWithoutFee = nonTaxableAmount + mulDown(taxableAmount, FixedPoint.ONE - swapFeePercentage);
            } else {
                amountInWithoutFee = amountsIn[i];
            }

            newBalances[i] = balances[i] + amountInWithoutFee;
        }

        uint256 newInvariant = mockComputeInvariant(amp, newBalances);
        uint256 invariantRatio = divDown(newInvariant, currentInvariant);

        if (invariantRatio > FixedPoint.ONE) {
            return mulDown(bptTotalSupply, invariantRatio - FixedPoint.ONE);
        } else {
            return 0;
        }
    }

    function mockComputeTokenInGivenExactBptOut(
        uint256 amp,
        uint256[] memory balances,
        uint256 tokenIndex,
        uint256 bptAmountOut,
        uint256 bptTotalSupply,
        uint256 currentInvariant,
        uint256 swapFeePercentage
    ) external view returns (uint256) {
        uint256 newInvariant = mulUp(divUp(bptTotalSupply + bptAmountOut, bptTotalSupply), currentInvariant);

        uint256 newBalanceTokenIndex = mockComputeBalance(amp, balances, newInvariant, tokenIndex);
        uint256 amountInWithoutFee = newBalanceTokenIndex - balances[tokenIndex];

        uint256 sumBalances = 0;
        for (uint256 i = 0; i < balances.length; ++i) {
            sumBalances += balances[i];
        }

        uint256 currentWeight = divUp(balances[tokenIndex], sumBalances);
        uint256 taxablePercentage = currentWeight.complement();
        uint256 taxableAmount = mulDown(amountInWithoutFee, taxablePercentage);
        uint256 nonTaxableAmount = amountInWithoutFee - taxableAmount;

        return nonTaxableAmount + divUp(taxableAmount, FixedPoint.ONE - swapFeePercentage);
    }

    function mockComputeBptInGivenExactTokensOut(
        uint256 amp,
        uint256[] memory balances,
        uint256[] memory amountsOut,
        uint256 bptTotalSupply,
        uint256 currentInvariant,
        uint256 swapFeePercentage
    ) external view returns (uint256) {
        uint256 sumBalances = 0;
        uint256 numTokens = balances.length;
        for (uint256 i = 0; i < numTokens; ++i) {
            sumBalances += balances[i];
        }

        uint256[] memory balanceRatiosWithoutFee = new uint256[](numTokens);
        uint256 invariantRatioWithoutFees = 0;
        for (uint256 i = 0; i < numTokens; ++i) {
            uint256 currentWeight = divDown(balances[i], sumBalances);
            balanceRatiosWithoutFee[i] = divDown(balances[i] - amountsOut[i], balances[i]);
            invariantRatioWithoutFees += mulDown(balanceRatiosWithoutFee[i], currentWeight);
        }

        uint256[] memory newBalances = new uint256[](numTokens);
        for (uint256 i = 0; i < numTokens; ++i) {
            uint256 amountOutWithFee;
            if (invariantRatioWithoutFees > balanceRatiosWithoutFee[i]) {
                uint256 nonTaxableAmount = mulUp(balances[i], invariantRatioWithoutFees.complement());
                uint256 taxableAmount = amountsOut[i] - nonTaxableAmount;
                amountOutWithFee = nonTaxableAmount + divUp(taxableAmount, FixedPoint.ONE - swapFeePercentage);
            } else {
                amountOutWithFee = amountsOut[i];
            }

            newBalances[i] = balances[i] - amountOutWithFee;
        }

        uint256 newInvariant = mockComputeInvariant(amp, newBalances);
        uint256 invariantRatio = divDown(newInvariant, currentInvariant);

        return mulUp(bptTotalSupply, invariantRatio.complement());
    }

    function mockComputeTokenOutGivenExactBptIn(
        uint256 amp,
        uint256[] memory balances,
        uint256 tokenIndex,
        uint256 bptAmountIn,
        uint256 bptTotalSupply,
        uint256 currentInvariant,
        uint256 swapFeePercentage
    ) external view returns (uint256) {
        uint256 newInvariant = mulUp(divUp(bptTotalSupply - bptAmountIn, bptTotalSupply), currentInvariant);

        uint256 newBalanceTokenIndex = mockComputeBalance(amp, balances, newInvariant, tokenIndex);
        uint256 amountOutWithoutFee = balances[tokenIndex] - newBalanceTokenIndex;

        uint256 sumBalances = 0;
        for (uint256 i = 0; i < balances.length; ++i) {
            sumBalances += balances[i];
        }

        uint256 currentWeight = divDown(balances[tokenIndex], sumBalances);
        uint256 taxablePercentage = currentWeight.complement();
        uint256 taxableAmount = mulUp(amountOutWithoutFee, taxablePercentage);
        uint256 nonTaxableAmount = amountOutWithoutFee - taxableAmount;

        return nonTaxableAmount + mulDown(taxableAmount, FixedPoint.ONE - swapFeePercentage);
    }

    function mockComputeBalance(
        uint256 amplificationParameter,
        uint256[] memory balances,
        uint256 invariant,
        uint256 tokenIndex
    ) public view returns (uint256) {
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
        uint256 c = (divUpRaw(inv2, ampTimesTotal * P_D) * StableMath.AMP_PRECISION) * balances[tokenIndex];
        uint256 b = sum + ((invariant / ampTimesTotal) * StableMath.AMP_PRECISION);
        uint256 prevTokenBalance = 0;
        uint256 tokenBalance = divUpRaw(inv2 + c, invariant + b);

        for (uint256 i = 0; i < 255; ++i) {
            prevTokenBalance = tokenBalance;

            tokenBalance = divUpRaw((tokenBalance * tokenBalance) + c, (tokenBalance * 2) + b - invariant);

            unchecked {
                if (tokenBalance > prevTokenBalance) {
                    if (tokenBalance - prevTokenBalance <= 1) {
                        return tokenBalance;
                    }
                } else if (prevTokenBalance - tokenBalance <= 1) {
                    return tokenBalance;
                }
            }
        }

        revert StableMath.StableGetBalanceDidntConverge();
    }
}
