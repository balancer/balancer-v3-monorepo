// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "./FixedPoint.sol";

// Some variables have non mixed case names (e.g. P_D) that relate to the mathematical derivations.
// solhint-disable private-vars-leading-underscore, var-name-mixedcase

library StableMath {
    using FixedPoint for uint256;

    /// @dev The iterations to calculate the invariant didn't converge
    error StableInvariantDidntConverge();

    /// @dev The iterations to calculate the balance didn't converge
    error StableGetBalanceDidntConverge();

    uint256 internal constant MIN_AMP = 1;
    uint256 internal constant MAX_AMP = 5000;
    uint256 internal constant AMP_PRECISION = 1e3;

    // Note on unchecked arithmetic:
    // This contract performs a large number of additions, subtractions, multiplications and divisions, often inside
    // loops. Since many of these operations are gas-sensitive (as they happen e.g. during a swap), it is important to
    // not make any unnecessary checks. We rely on a set of invariants to avoid having to use checked arithmetic,
    // including:
    //  - the amplification parameter is bounded by MAX_AMP * AMP_PRECISION, which fits in 23 bits
    //
    // This means e.g. we can safely multiply a balance by the amplification parameter without worrying about overflow.

    // About swap fees on add and remove liquidity:
    // Any add or remove that is not perfectly balanced (e.g. all single token operations) is mathematically
    // equivalent to a perfectly balanced add or remove followed by a series of swaps. Since these swaps would charge
    // swap fees, it follows that unbalanced adds and removes should as well.
    // On these operations, we split the token amounts in 'taxable' and 'non-taxable' portions, where the 'taxable' part
    // is the one to which swap fees are applied.

    // Computes the invariant given the current balances, using the Newton-Raphson approximation.
    // The amplification parameter equals: A n^(n-1)
    // See: https://github.com/curvefi/curve-contract/blob/b0bbf77f8f93c9c5f4e415bce9cd71f0cdee960e/contracts/pool-templates/base/SwapTemplateBase.vy#L206
    // solhint-disable-previous-line max-line-length

    function computeInvariant(
        uint256 amplificationParameter,
        uint256[] memory balances
    ) internal pure returns (uint256) {
        /**********************************************************************************************
        // invariant                                                                                 //
        // D = invariant                                                  D^(n+1)                    //
        // A = amplification coefficient      A  n^n S + D = A D n^n + -----------                   //
        // S = sum of balances                                             n^n P                     //
        // P = product of balances                                                                   //
        // n = number of tokens                                                                      //
        **********************************************************************************************/

        // Always round down, to match Vyper's arithmetic (which always truncates).
        uint256 sum = 0; // S in the Curve version
        uint256 numTokens = balances.length;
        for (uint256 i = 0; i < numTokens; ++i) {
            sum = sum + balances[i];
        }
        if (sum == 0) {
            return 0;
        }

        uint256 prevInvariant; // Dprev in the Curve version
        uint256 invariant = sum; // D in the Curve version
        uint256 ampTimesTotal = amplificationParameter * numTokens; // Ann in the Curve version

        for (uint256 i = 0; i < 255; ++i) {
            uint256 D_P = invariant;
            for (uint256 j = 0; j < numTokens; ++j) {
                D_P = (D_P * invariant) / (balances[j] * numTokens);
            }

            prevInvariant = invariant;

            invariant =
                ((((ampTimesTotal * sum) / AMP_PRECISION) + (D_P * numTokens)) * invariant) /
                ((((ampTimesTotal - AMP_PRECISION) * invariant) / AMP_PRECISION) + ((numTokens + 1) * D_P));

            unchecked {
                // We are explicitly checking the magnitudes here, so can use unchecked math.
                if (invariant > prevInvariant) {
                    if (invariant - prevInvariant <= 1) {
                        return invariant;
                    }
                } else if (prevInvariant - invariant <= 1) {
                    return invariant;
                }
            }
        }

        revert StableInvariantDidntConverge();
    }

    // Computes how many tokens can be taken out of a pool if `tokenAmountIn` are sent, given the current balances.
    // The amplification parameter equals: A n^(n-1)
    function computeOutGivenExactIn(
        uint256 amplificationParameter,
        uint256[] memory balances,
        uint256 tokenIndexIn,
        uint256 tokenIndexOut,
        uint256 tokenAmountIn,
        uint256 invariant
    ) internal pure returns (uint256) {
        /**************************************************************************************************************
        // outGivenExactIn token x for y - polynomial equation to solve                                              //
        // ay = amount out to calculate                                                                              //
        // by = balance token out                                                                                    //
        // y = by - ay (finalBalanceOut)                                                                             //
        // D = invariant                                               D                     D^(n+1)                 //
        // A = amplification coefficient               y^2 + ( S + ----------  - D) * y -  ------------- = 0         //
        // n = number of tokens                                    (A * n^n)               A * n^2n * P              //
        // S = sum of final balances but y                                                                           //
        // P = product of final balances but y                                                                       //
        **************************************************************************************************************/

        // Amount out, so we round down overall.
        balances[tokenIndexIn] += tokenAmountIn;

        uint256 finalBalanceOut = computeBalance(amplificationParameter, balances, invariant, tokenIndexOut);

        // No need to use checked arithmetic since `tokenAmountIn` was actually added to the same balance right before
        // calling `_getTokenBalanceGivenInvariantAndAllOtherBalances` which doesn't alter the balances array.
        unchecked {
            balances[tokenIndexIn] -= tokenAmountIn;
        }

        return balances[tokenIndexOut] - finalBalanceOut - 1;
    }

    // Computes how many tokens must be sent to a pool if `tokenAmountOut` are sent given the
    // current balances, using the Newton-Raphson approximation.
    // The amplification parameter equals: A n^(n-1)
    function computeInGivenExactOut(
        uint256 amplificationParameter,
        uint256[] memory balances,
        uint256 tokenIndexIn,
        uint256 tokenIndexOut,
        uint256 tokenAmountOut,
        uint256 invariant
    ) internal pure returns (uint256) {
        /**************************************************************************************************************
        // inGivenExactOut token x for y - polynomial equation to solve                                              //
        // ax = amount in to calculate                                                                               //
        // bx = balance token in                                                                                     //
        // x = bx + ax (finalBalanceIn)                                                                              //
        // D = invariant                                                D                     D^(n+1)                //
        // A = amplification coefficient               x^2 + ( S + ----------  - D) * x -  ------------- = 0         //
        // n = number of tokens                                     (A * n^n)               A * n^2n * P             //
        // S = sum of final balances but x                                                                           //
        // P = product of final balances but x                                                                       //
        **************************************************************************************************************/

        // Amount in, so we round up overall.
        balances[tokenIndexOut] -= tokenAmountOut;

        uint256 finalBalanceIn = computeBalance(amplificationParameter, balances, invariant, tokenIndexIn);

        // No need to use checked arithmetic since `tokenAmountOut` was actually subtracted from the same balance right
        // before calling `_getTokenBalanceGivenInvariantAndAllOtherBalances` which doesn't alter the balances array.
        unchecked {
            balances[tokenIndexOut] += tokenAmountOut;
        }

        return finalBalanceIn - balances[tokenIndexIn] + 1;
    }

    function _calcBptOutGivenExactTokensIn(
        uint256 amp,
        uint256[] memory balances,
        uint256[] memory amountsIn,
        uint256 bptTotalSupply,
        uint256 currentInvariant,
        uint256 swapFeePercentage
    ) internal pure returns (uint256) {
        // BPT out, so we round down overall.

        // First loop calculates the sum of all token balances, which will be used to calculate
        // the current weights of each token, relative to this sum
        uint256 sumBalances = 0;
        for (uint256 i = 0; i < balances.length; ++i) {
            sumBalances += balances[i];
        }

        // Calculate the weighted balance ratio without considering fees
        uint256[] memory balanceRatiosWithFee = new uint256[](amountsIn.length);
        // The weighted sum of token balance ratios with fee
        uint256 invariantRatioWithFees = 0;
        for (uint256 i = 0; i < balances.length; ++i) {
            uint256 currentWeight = balances[i].divDown(sumBalances);
            balanceRatiosWithFee[i] = (balances[i] + amountsIn[i]).divDown(balances[i]);
            invariantRatioWithFees = invariantRatioWithFees + (balanceRatiosWithFee[i].mulDown(currentWeight));
        }

        // Second loop calculates new amounts in, taking into account the fee on the percentage excess
        uint256[] memory newBalances = new uint256[](balances.length);
        for (uint256 i = 0; i < balances.length; ++i) {
            uint256 amountInWithoutFee;

            // Check if the balance ratio is greater than the ideal ratio to charge fees or not
            if (balanceRatiosWithFee[i] > invariantRatioWithFees) {
                uint256 nonTaxableAmount = balances[i].mulDown(invariantRatioWithFees - FixedPoint.ONE);
                uint256 taxableAmount = amountsIn[i] - nonTaxableAmount;
                amountInWithoutFee = nonTaxableAmount + (taxableAmount.mulDown(FixedPoint.ONE - swapFeePercentage));
            } else {
                amountInWithoutFee = amountsIn[i];
            }

            newBalances[i] = balances[i] + amountInWithoutFee;
        }

        uint256 newInvariant = computeInvariant(amp, newBalances);
        uint256 invariantRatio = newInvariant.divDown(currentInvariant);

        // If the invariant didn't increase for any reason, we simply don't mint BPT
        if (invariantRatio > FixedPoint.ONE) {
            return bptTotalSupply.mulDown(invariantRatio - FixedPoint.ONE);
        } else {
            return 0;
        }
    }

    function _calcTokenInGivenExactBptOut(
        uint256 amp,
        uint256[] memory balances,
        uint256 tokenIndex,
        uint256 bptAmountOut,
        uint256 bptTotalSupply,
        uint256 currentInvariant,
        uint256 swapFeePercentage
    ) internal pure returns (uint256) {
        // Token in, so we round up overall.

        uint256 newInvariant = (bptTotalSupply + bptAmountOut).divUp(bptTotalSupply).mulUp(currentInvariant);

        // Calculate amount in without fee.
        uint256 newBalanceTokenIndex = computeBalance(amp, balances, newInvariant, tokenIndex);
        uint256 amountInWithoutFee = newBalanceTokenIndex - balances[tokenIndex];

        // First calculate the sum of all token balances, which will be used to calculate
        // the current weight of each token
        uint256 sumBalances = 0;
        for (uint256 i = 0; i < balances.length; ++i) {
            sumBalances += balances[i];
        }

        // We can now compute how much extra balance is being deposited and used in virtual swaps, and charge swap fees
        // accordingly.
        uint256 currentWeight = balances[tokenIndex].divDown(sumBalances);
        uint256 taxablePercentage = currentWeight.complement();
        uint256 taxableAmount = amountInWithoutFee.mulUp(taxablePercentage);
        uint256 nonTaxableAmount = amountInWithoutFee - taxableAmount;

        return nonTaxableAmount + (taxableAmount.divUp(FixedPoint.ONE - swapFeePercentage));
    }

    /**
     * @dev Flow of calculations:
     * amountsTokenOut -> amountsOutProportional ->
     * amountOutPercentageExcess -> amountOutBeforeFee -> newInvariant -> amountBPTIn
     */
    function _calcBptInGivenExactTokensOut(
        uint256 amp,
        uint256[] memory balances,
        uint256[] memory amountsOut,
        uint256 bptTotalSupply,
        uint256 currentInvariant,
        uint256 swapFeePercentage
    ) internal pure returns (uint256) {
        // BPT in, so we round up overall.

        // First loop calculates the sum of all token balances, which will be used to calculate
        // the current weights of each token relative to this sum
        uint256 sumBalances = 0;
        for (uint256 i = 0; i < balances.length; ++i) {
            sumBalances += balances[i];
        }

        // Calculate the weighted balance ratio without considering fees
        uint256[] memory balanceRatiosWithoutFee = new uint256[](amountsOut.length);
        uint256 invariantRatioWithoutFees = 0;
        for (uint256 i = 0; i < balances.length; ++i) {
            uint256 currentWeight = balances[i].divUp(sumBalances);
            balanceRatiosWithoutFee[i] = (balances[i] - amountsOut[i]).divUp(balances[i]);
            invariantRatioWithoutFees = invariantRatioWithoutFees + (balanceRatiosWithoutFee[i].mulUp(currentWeight));
        }

        // Second loop calculates new amounts in, taking into account the fee on the percentage excess
        uint256[] memory newBalances = new uint256[](balances.length);
        for (uint256 i = 0; i < balances.length; ++i) {
            // Swap fees are typically charged on 'token in', but there is no 'token in' here, so we apply it to
            // 'token out'. This results in slightly larger price impact.

            uint256 amountOutWithFee;
            if (invariantRatioWithoutFees > balanceRatiosWithoutFee[i]) {
                uint256 nonTaxableAmount = balances[i].mulDown(invariantRatioWithoutFees.complement());
                uint256 taxableAmount = amountsOut[i] - nonTaxableAmount;
                amountOutWithFee = nonTaxableAmount + (taxableAmount.divUp(FixedPoint.ONE - swapFeePercentage));
            } else {
                amountOutWithFee = amountsOut[i];
            }

            newBalances[i] = balances[i] - amountOutWithFee;
        }

        uint256 newInvariant = computeInvariant(amp, newBalances);
        uint256 invariantRatio = newInvariant.divDown(currentInvariant);

        // return amountBPTIn
        return bptTotalSupply.mulUp(invariantRatio.complement());
    }

    function _calcTokenOutGivenExactBptIn(
        uint256 amp,
        uint256[] memory balances,
        uint256 tokenIndex,
        uint256 bptAmountIn,
        uint256 bptTotalSupply,
        uint256 currentInvariant,
        uint256 swapFeePercentage
    ) internal pure returns (uint256) {
        // Token out, so we round down overall.

        uint256 newInvariant = (bptTotalSupply - bptAmountIn).divUp(bptTotalSupply).mulUp(currentInvariant);

        // Calculate amount out without fee
        uint256 newBalanceTokenIndex = computeBalance(amp, balances, newInvariant, tokenIndex);
        uint256 amountOutWithoutFee = balances[tokenIndex] - newBalanceTokenIndex;

        // First calculate the sum of all token balances, which will be used to calculate
        // the current weight of each token
        uint256 sumBalances = 0;
        for (uint256 i = 0; i < balances.length; ++i) {
            sumBalances += balances[i];
        }

        // We can now compute how much excess balance is being withdrawn as a result of the virtual swaps, which result
        // in swap fees.
        uint256 currentWeight = balances[tokenIndex].divDown(sumBalances);
        uint256 taxablePercentage = currentWeight.complement();

        // Swap fees are typically charged on 'token in', but there is no 'token in' here, so we apply it
        // to 'token out'. This results in slightly larger price impact. Fees are rounded up.
        uint256 taxableAmount = amountOutWithoutFee.mulUp(taxablePercentage);
        uint256 nonTaxableAmount = amountOutWithoutFee - taxableAmount;

        return nonTaxableAmount + (taxableAmount.mulDown(FixedPoint.ONE - swapFeePercentage));
    }

    // This function calculates the balance of a given token (tokenIndex)
    // given all the other balances and the invariant
    function computeBalance(
        uint256 amplificationParameter,
        uint256[] memory balances,
        uint256 invariant,
        uint256 tokenIndex
    ) internal pure returns (uint256) {
        // Rounds result up overall
        uint256 ampTimesTotal = amplificationParameter * balances.length;
        uint256 sum = balances[0];
        uint256 P_D = balances[0] * balances.length;
        for (uint256 j = 1; j < balances.length; ++j) {
            P_D = (P_D * balances[j] * balances.length) / invariant;
            sum = sum + balances[j];
        }
        sum = sum - balances[tokenIndex];

        // Use divUpRaw with inv2, as it is a "raw" 36 decimal value
        uint256 inv2 = invariant * invariant;
        // We remove the balance from c by multiplying it
        uint256 c = (inv2.divUpRaw(ampTimesTotal * P_D) * AMP_PRECISION) * balances[tokenIndex];
        uint256 b = sum + ((invariant / ampTimesTotal) * AMP_PRECISION);
        // We iterate to find the balance
        uint256 prevTokenBalance = 0;
        // We multiply the first iteration outside the loop with the invariant to set the value of the
        // initial approximation.
        uint256 tokenBalance = (inv2 + c).divUpRaw(invariant + b);

        for (uint256 i = 0; i < 255; ++i) {
            prevTokenBalance = tokenBalance;

            // Use divUpRaw with tokenBalance, as it is a "raw" 36 decimal value
            tokenBalance = ((tokenBalance * tokenBalance) + c).divUpRaw((tokenBalance * 2) + b - invariant);

            // We are explicitly checking the magnitudes here, so can use unchecked math.
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

        revert StableGetBalanceDidntConverge();
    }
}
