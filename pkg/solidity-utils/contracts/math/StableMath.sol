// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { FixedPoint } from "./FixedPoint.sol";

/**
 * @notice Stable Pool math library based on Curve's `StableSwap`.
 * @dev See https://docs.curve.fi/references/whitepapers/stableswap/
 *
 * For security reasons, to help ensure that for all possible "round trip" paths the caller always receives the same
 * or fewer tokens than supplied, we have used precise math (i.e., '*', '/' vs. FixedPoint) whenever possible, and
 * chosen the rounding direction to favor the protocol elsewhere.
 *
 * `computeInvariant` does not use the rounding direction from `IBasePool`, effectively always rounding down to match
 * the Curve implementation.
 */
library StableMath {
    using FixedPoint for uint256;

    /// @notice The imbalance ratio exceeds the maximum allowed.
    error MaxImbalanceRatioExceeded();

    // Some variables have non mixed case names (e.g. P_D) that relate to the mathematical derivations.
    // solhint-disable private-vars-leading-underscore, var-name-mixedcase

    /// @notice The iterations to calculate the invariant didn't converge.
    error StableInvariantDidNotConverge();

    /// @notice The iterations to calculate the balance didn't converge.
    error StableComputeBalanceDidNotConverge();

    // The max token count is limited by the math, and is less than the Vault's maximum.
    uint256 public constant MAX_STABLE_TOKENS = 5;

    uint256 internal constant MIN_AMP = 1;
    uint256 internal constant MAX_AMP = 50000;
    uint256 internal constant AMP_PRECISION = 1e3;

    // Maximum allowed ratio between the highest and lowest token balances in the pool.
    uint256 internal constant MAX_IMBALANCE_RATIO = 10_000;

    // Invariant growth limit: non-proportional add cannot cause the invariant to increase by more than this ratio.
    uint256 internal constant MIN_INVARIANT_RATIO = 60e16; // 60%
    // Invariant shrink limit: non-proportional remove cannot cause the invariant to decrease by less than this ratio.
    uint256 internal constant MAX_INVARIANT_RATIO = 500e16; // 500%

    // About swap fees on add and remove liquidity:
    // Any add or remove that is not perfectly balanced (e.g. all single token operations) is mathematically
    // equivalent to a perfectly balanced add or remove followed by a series of swaps. Since these swaps would charge
    // swap fees, it follows that unbalanced adds and removes should as well.
    //
    // On these operations, we split the token amounts in 'taxable' and 'non-taxable' portions, where the 'taxable' part
    // is the one to which swap fees are applied.

    // See: https://github.com/curvefi/curve-contract/blob/b0bbf77f8f93c9c5f4e415bce9cd71f0cdee960e/contracts/pool-templates/base/SwapTemplateBase.vy#L206
    // solhint-disable-previous-line max-line-length

    /**
     * @notice Computes the invariant given the current balances.
     * @dev It uses the Newton-Raphson approximation. The amplification parameter is given by: A n^(n-1).
     * There is no closed-form solution, so the calculation is iterative and may revert.
     *
     * @param amplificationParameter The current amplification parameter
     * @param balances The current balances
     * @return invariant The calculated invariant of the pool
     */
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

        revert StableInvariantDidNotConverge();
    }

    /**
     * @notice Computes the required `amountOut` of tokenOut, for `tokenAmountIn` of tokenIn.
     * @dev The calculation uses the Newton-Raphson approximation. The amplification parameter is given by: A n^(n-1).
     * @param amplificationParameter The current amplification factor
     * @param balances The current pool balances
     * @param tokenIndexIn The index of tokenIn
     * @param tokenIndexOut The index of tokenOut
     * @param tokenAmountIn The exact amount of tokenIn specified for the swap
     * @param invariant The current invariant
     * @return amountOut The calculated amount of tokenOut required for the swap
     */
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

        balances[tokenIndexIn] += tokenAmountIn;

        // `computeBalance` rounds up.
        uint256 finalBalanceOut = computeBalance(amplificationParameter, balances, invariant, tokenIndexOut);

        // No need to use checked arithmetic since `tokenAmountIn` was actually added to the same balance right before
        // calling `computeBalance`, which doesn't alter the balances array.
        unchecked {
            balances[tokenIndexIn] -= tokenAmountIn;
        }

        // Amount out, so we round down overall.
        return balances[tokenIndexOut] - finalBalanceOut - 1;
    }

    /**
     * @notice Computes the required `amountIn` of tokenIn, for `tokenAmountOut` of tokenOut.
     * @dev The calculation uses the Newton-Raphson approximation. The amplification parameter is given by: A n^(n-1).
     * @param amplificationParameter The current amplification factor
     * @param balances The current pool balances
     * @param tokenIndexIn The index of tokenIn
     * @param tokenIndexOut The index of tokenOut
     * @param tokenAmountOut The exact amount of tokenOut specified for the swap
     * @param invariant The current invariant
     * @return amountIn The calculated amount of tokenIn required for the swap
     */
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

        balances[tokenIndexOut] -= tokenAmountOut;

        // `computeBalance` rounds up.
        uint256 finalBalanceIn = computeBalance(amplificationParameter, balances, invariant, tokenIndexIn);

        // No need to use checked arithmetic since `tokenAmountOut` was actually subtracted from the same balance right
        // before calling `computeBalance`, which doesn't alter the balances array.
        unchecked {
            balances[tokenIndexOut] += tokenAmountOut;
        }

        // Amount in, so we round up overall.
        return finalBalanceIn - balances[tokenIndexIn] + 1;
    }

    /**
     * @notice Calculate the balance of a given token (at tokenIndex), given all other balances and the invariant.
     * @dev Rounds result up overall. There is no closed-form solution, so the calculation is iterative and may revert.
     * @param amplificationParameter The current amplification factor
     * @param balances The current pool balances
     * @param invariant The current invariant
     * @param tokenIndex The index of the token balance we are calculating
     * @return tokenBalance The adjusted balance of the token at `tokenIn` that matches the given invariant
     */
    function computeBalance(
        uint256 amplificationParameter,
        uint256[] memory balances,
        uint256 invariant,
        uint256 tokenIndex
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

        // Use divUpRaw with inv2, as it is a "raw" 36 decimal value.
        uint256 inv2 = invariant * invariant;
        // We remove the balance from c by multiplying it.
        uint256 c = (inv2 * AMP_PRECISION).divUpRaw(ampTimesTotal * P_D) * balances[tokenIndex];
        uint256 b = sum + ((invariant * AMP_PRECISION) / ampTimesTotal);
        // We iterate to find the balance.
        uint256 prevTokenBalance = 0;
        // We multiply the first iteration outside the loop with the invariant to set the value of the
        // initial approximation.
        uint256 tokenBalance = (inv2 + c).divUpRaw(invariant + b);

        for (uint256 i = 0; i < 255; ++i) {
            prevTokenBalance = tokenBalance;

            // Use divUpRaw with tokenBalance, as it is a "raw" 36 decimal value.
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

        revert StableComputeBalanceDidNotConverge();
    }

    /**
     * @notice Get the minimum and maximum balances from an array of balances.
     * @param balancesScaled18 Array of token balances scaled to 18 decimals
     * @return minBalance The minimum balance found in the array
     * @return maxBalance The maximum balance found in the array
     */
    function getMinAndMaxBalances(
        uint256[] memory balancesScaled18
    ) internal pure returns (uint256 minBalance, uint256 maxBalance) {
        minBalance = balancesScaled18[0];
        maxBalance = minBalance;

        uint256 length = balancesScaled18.length;
        for (uint256 i = 1; i < length; i++) {
            uint256 balance = balancesScaled18[i];
            if (balance < minBalance) {
                minBalance = balance;
            }

            if (balance > maxBalance) {
                maxBalance = balance;
            }
        }
    }

    /**
     * @notice Ensure that the balances are within the maximum imbalance ratio.
     * @param minBalance The minimum balance among the tokens
     * @param maxBalance The maximum balance among the tokens
     */
    function ensureBalancesWithinMaxImbalanceRange(uint256 minBalance, uint256 maxBalance) internal pure {
        uint256 imbalance = maxBalance / minBalance;
        if (imbalance >= MAX_IMBALANCE_RATIO) {
            revert MaxImbalanceRatioExceeded();
        }
    }
}
