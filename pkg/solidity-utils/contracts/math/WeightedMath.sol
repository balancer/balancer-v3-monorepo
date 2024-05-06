// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "./FixedPoint.sol";
import "./LogExpMath.sol";

library WeightedMath {
    using FixedPoint for uint256;

    // For security reasons, to help ensure that for all possible "round trip" paths
    // the caller always receives the same or fewer tokens than supplied,
    // we have chosen the rounding direction to favor the protocol in all cases.

    /// @dev User Attempted to burn less BPT than allowed for a specific amountOut.
    error MinBPTInForTokenOut();

    /// @dev User attempted to mint more BPT than allowed for a specific amountIn.
    error MaxOutBptForTokenIn();

    /// @dev User attempted to extract a disproportionate amountOut of tokens from a pool.
    error MaxOutRatio();

    /// @dev User attempted to add a disproportionate amountIn of tokens to a pool.
    error MaxInRatio();

    /**
     * @dev Error thrown when the calculated invariant is zero, indicating an issue with the invariant calculation.
     * Most commonly, this happens when a token balance is zero.
     */
    error ZeroInvariant();

    // A minimum normalized weight imposes a maximum weight ratio. We need this due to limitations in the
    // implementation of the power function, as these ratios are often exponents.
    uint256 internal constant _MIN_WEIGHT = 0.01e18;

    // Pool limits that arise from limitations in the fixed point power function (and the imposed 1:100 maximum weight
    // ratio).

    // Swap limits: amounts swapped may not be larger than this percentage of the total balance.
    uint256 internal constant _MAX_IN_RATIO = 0.3e18;
    uint256 internal constant _MAX_OUT_RATIO = 0.3e18;

    // Invariant growth limit: non-proportional joins cannot cause the invariant to increase by more than this ratio.
    uint256 internal constant _MAX_INVARIANT_RATIO = 3e18;
    // Invariant shrink limit: non-proportional exits cannot cause the invariant to decrease by less than this ratio.
    uint256 internal constant _MIN_INVARIANT_RATIO = 0.7e18;

    // About swap fees on joins and exits:
    // Any join or exit that is not perfectly balanced (e.g. all single token joins or exits) is mathematically
    // equivalent to a perfectly balanced join or exit followed by a series of swaps. Since these swaps would charge
    // swap fees, it follows that (some) joins and exits should as well.
    // On these operations, we split the token amounts in 'taxable' and 'non-taxable' portions, where the 'taxable' part
    // is the one to which swap fees are applied.

    // Invariant is used to collect protocol swap fees by comparing its value between two times.
    // So we can round always to the same direction. It is also used to initiate the BPT amount
    // and, because there is a minimum BPT, we round down the invariant.
    function computeInvariant(
        uint256[] memory normalizedWeights,
        uint256[] memory balances
    ) internal pure returns (uint256 invariant) {
        /**********************************************************************************************
        // invariant               _____                                                             //
        // wi = weight index i      | |      wi                                                      //
        // bi = balance index i     | |  bi ^   = i                                                  //
        // i = invariant                                                                             //
        **********************************************************************************************/

        invariant = FixedPoint.ONE;
        for (uint256 i = 0; i < normalizedWeights.length; ++i) {
            invariant = invariant.mulDown(balances[i].powDown(normalizedWeights[i]));
        }

        if (invariant == 0) {
            revert ZeroInvariant();
        }
    }

    function computeBalanceOutGivenInvariant(
        uint256 currentBalance,
        uint256 weight,
        uint256 invariantRatio
    ) internal pure returns (uint256 invariant) {
        /******************************************************************************************
        // calculateBalanceGivenInvariant                                                       //
        // o = balanceOut                                                                        //
        // b = balanceIn                      (1 / w)                                            //
        // w = weight              o = b * i ^                                                   //
        // i = invariantRatio                                                                    //
        ******************************************************************************************/

        // Rounds result up overall.

        // Calculate by how much the token balance has to increase to match the invariantRatio.
        uint256 balanceRatio = invariantRatio.powUp(FixedPoint.ONE.divUp(weight));

        return currentBalance.mulUp(balanceRatio);
    }

    // Computes how many tokens can be taken out of a pool if `amountIn` are sent, given the
    // current balances and weights.
    function computeOutGivenExactIn(
        uint256 balanceIn,
        uint256 weightIn,
        uint256 balanceOut,
        uint256 weightOut,
        uint256 amountIn
    ) internal pure returns (uint256) {
        /**********************************************************************************************
        // outGivenExactIn                                                                                //
        // aO = amountOut                                                                            //
        // bO = balanceOut                                                                           //
        // bI = balanceIn              /      /            bI             \    (wI / wO) \           //
        // aI = amountIn    aO = bO * |  1 - | --------------------------  | ^            |          //
        // wI = weightIn               \      \       ( bI + aI )         /              /           //
        // wO = weightOut                                                                            //
        **********************************************************************************************/

        // Amount out, so we round down overall.

        // The multiplication rounds down, and the subtrahend (power) rounds up (so the base rounds up too).
        // Because bI / (bI + aI) <= 1, the exponent rounds down.

        // Cannot exceed maximum in ratio.
        if (amountIn > balanceIn.mulDown(_MAX_IN_RATIO)) {
            revert MaxInRatio();
        }

        uint256 denominator = balanceIn + amountIn;
        uint256 base = balanceIn.divUp(denominator);
        uint256 exponent = weightIn.divDown(weightOut);
        uint256 power = base.powUp(exponent);

        // Because of rounding up, power can be greater than one. Using complement prevents reverts.
        return balanceOut.mulDown(power.complement());
    }

    // Computes how many tokens must be sent to a pool in order to take `amountOut`, given the
    // current balances and weights.
    function computeInGivenExactOut(
        uint256 balanceIn,
        uint256 weightIn,
        uint256 balanceOut,
        uint256 weightOut,
        uint256 amountOut
    ) internal pure returns (uint256) {
        /**********************************************************************************************
        // inGivenExactOut                                                                                //
        // aO = amountOut                                                                            //
        // bO = balanceOut                                                                           //
        // bI = balanceIn              /  /            bO             \    (wO / wI)      \          //
        // aI = amountIn    aI = bI * |  | --------------------------  | ^            - 1  |         //
        // wI = weightIn               \  \       ( bO - aO )         /                   /          //
        // wO = weightOut                                                                            //
        **********************************************************************************************/

        // Amount in, so we round up overall.

        // The multiplication rounds up, and the power rounds up (so the base rounds up too).
        // Because b0 / (b0 - a0) >= 1, the exponent rounds up.

        // Cannot exceed maximum out ratio.
        if (amountOut > balanceOut.mulDown(_MAX_OUT_RATIO)) {
            revert MaxOutRatio();
        }

        uint256 base = balanceOut.divUp(balanceOut - amountOut);
        uint256 exponent = weightOut.divUp(weightIn);
        uint256 power = base.powUp(exponent);

        // Because the base is larger than one (and the power rounds up), the power should always be larger than one, so
        // the following subtraction should never revert.
        uint256 ratio = power - FixedPoint.ONE;

        return balanceIn.mulUp(ratio);
    }

    function computeBptOutGivenExactTokensIn(
        uint256[] memory balances,
        uint256[] memory normalizedWeights,
        uint256[] memory amountsIn,
        uint256 bptTotalSupply,
        uint256 swapFeePercentage
    ) internal pure returns (uint256) {
        // BPT out, so we round down overall.

        uint256[] memory balanceRatiosWithFee = new uint256[](amountsIn.length);

        uint256 invariantRatioWithFees = 0;
        for (uint256 i = 0; i < balances.length; ++i) {
            // Round down to ultimately reduce the ratios with fees,
            // which will be used later when calculating the `nonTaxableAmount` for each token.
            balanceRatiosWithFee[i] = (balances[i] + amountsIn[i]).divDown(balances[i]);
            invariantRatioWithFees += balanceRatiosWithFee[i].mulDown(normalizedWeights[i]);
        }

        uint256 invariantRatio = computeJoinExactTokensInInvariantRatio(
            balances,
            normalizedWeights,
            amountsIn,
            balanceRatiosWithFee,
            invariantRatioWithFees,
            swapFeePercentage
        );

        // If the invariant didn't increase for any reason, we simply don't mint BPT.
        if (invariantRatio > FixedPoint.ONE) {
            // Round down to reduce the amount of BPT out.
            return bptTotalSupply.mulDown(invariantRatio - FixedPoint.ONE);
        } else {
            return 0;
        }
    }

    function computeBptOutGivenExactTokenIn(
        uint256 balance,
        uint256 normalizedWeight,
        uint256 amountIn,
        uint256 bptTotalSupply,
        uint256 swapFeePercentage
    ) internal pure returns (uint256) {
        // BPT out, so we round down overall.

        uint256 amountInWithoutFee;
        {
            // Round down to ultimately reduce the ratios with fees,
            // which will be used later when calculating the `nonTaxableAmount` for tokenIn.
            uint256 balanceRatioWithFee = (balance + amountIn).divDown(balance);
            // The use of `normalizedWeight.complement()` assumes that the sum of all weights equals FixedPoint.ONE.
            // This may not be the case when weights are stored in a denormalized format or during a gradual weight
            // change due to rounding errors during normalization or interpolation. This will result in a small
            // difference between the output of this function and the equivalent `computeBptOutGivenExactTokensIn` call.
            uint256 invariantRatioWithFees = balanceRatioWithFee.mulDown(normalizedWeight) +
                normalizedWeight.complement();

            // Charge fees only when the balance ratio is greater than the ideal (proportional) ratio.
            if (balanceRatioWithFee > invariantRatioWithFees) {
                // `invariantRatioWithFees` might be less than FixedPoint.ONE in edge cases due to rounding errors,
                // particularly if the weights don't exactly add up to 100%. Round accordingly to ultimately lower the
                // `amountInWithoutFee`, consequently reducing the `balanceRatio`; we prioritize minimizing the
                // `nonTaxableAmount` over the `taxableAmount`.
                uint256 nonTaxableAmount = invariantRatioWithFees > FixedPoint.ONE
                    ? balance.mulDown(invariantRatioWithFees - FixedPoint.ONE)
                    : 0;
                uint256 taxableAmount = amountIn - nonTaxableAmount;
                uint256 swapFee = taxableAmount.mulUp(swapFeePercentage);

                amountInWithoutFee = nonTaxableAmount + taxableAmount - swapFee;
            } else {
                amountInWithoutFee = amountIn;

                // If a token's amount in is not being charged a swap fee then it might be zero.
                // In this case, it's clear that the sender should receive no BPT.
                if (amountInWithoutFee == 0) {
                    return 0;
                }
            }
        }

        // Round down the `balanceRatio` to lower the `invariantRatio`.
        uint256 balanceRatio = (balance + amountInWithoutFee).divDown(balance);

        // Round down the `invariantRatio` to reduce the BPT out.
        uint256 invariantRatio = balanceRatio.powDown(normalizedWeight);

        // If the invariant didn't increase for any reason, we simply don't mint BPT.
        if (invariantRatio > FixedPoint.ONE) {
            // Round down to reduce the amount of BPT out.
            return bptTotalSupply.mulDown(invariantRatio - FixedPoint.ONE);
        } else {
            return 0;
        }
    }

    /// @dev Intermediate function to avoid stack-too-deep errors.
    function computeJoinExactTokensInInvariantRatio(
        uint256[] memory balances,
        uint256[] memory normalizedWeights,
        uint256[] memory amountsIn,
        uint256[] memory balanceRatiosWithFee,
        uint256 invariantRatioWithFees,
        uint256 swapFeePercentage
    ) internal pure returns (uint256 invariantRatio) {
        // Swap fees are charged on all tokens that are being added in a larger proportion than the overall invariant
        // increase.
        invariantRatio = FixedPoint.ONE;

        for (uint256 i = 0; i < balances.length; ++i) {
            uint256 amountInWithoutFee;

            // Charge fees only when the balance ratio is greater than the ideal (proportional) ratio.
            if (balanceRatiosWithFee[i] > invariantRatioWithFees) {
                // `invariantRatioWithFees` might be less than FixedPoint.ONE in edge cases due to rounding errors,
                // particularly if the weights don't exactly add up to 100%. Round accordingly to ultimately lower the
                // `amountInWithoutFee`, consequently reducing the `balanceRatio`.
                uint256 nonTaxableAmount = invariantRatioWithFees > FixedPoint.ONE
                    ? balances[i].mulDown(invariantRatioWithFees - FixedPoint.ONE)
                    : 0;
                uint256 swapFee = (amountsIn[i] - nonTaxableAmount).mulUp(swapFeePercentage);

                amountInWithoutFee = amountsIn[i] - swapFee;
            } else {
                amountInWithoutFee = amountsIn[i];

                // If a token's amount in is not being charged a swap fee then it might be zero (e.g. when joining a
                // Pool with only a subset of tokens). In this case, `balanceRatio` will equal `FixedPoint.ONE`, and
                // the `invariantRatio` will not change at all. We therefore skip to the next iteration, avoiding
                // the costly `powDown` call.
                if (amountInWithoutFee == 0) {
                    continue;
                }
            }

            // Round down the `balanceRatio` to lower the `invariantRatio`.
            uint256 balanceRatio = (balances[i] + amountInWithoutFee).divDown(balances[i]);

            // Round down the `invariantRatio` to reduce the BPT out.
            invariantRatio = invariantRatio.mulDown(balanceRatio.powDown(normalizedWeights[i]));
        }
    }

    function computeTokenInGivenExactBptOut(
        uint256 balance,
        uint256 normalizedWeight,
        uint256 bptAmountOut,
        uint256 bptTotalSupply,
        uint256 swapFeePercentage
    ) internal pure returns (uint256) {
        /******************************************************************************************
        // tokenInForExactBPTOut                                                                 //
        // a = amountIn                                                                          //
        // b = balance                      /  /  ( totalBPT + bptOut )    \    (1 / w)       \  //
        // bptOut = bptAmountOut   a = b * |  | --------------------------  | ^          - 1  |  //
        // bpt = totalBPT                   \  \       totalBPT            /                  /  //
        // w = weight                                                                            //
        ******************************************************************************************/

        // Token in, so we round up overall.

        // The multiplication rounds up, and the power rounds up (so the base rounds up too).
        // Because (totalBPT + bptOut) / totalBPT >= 1, the exponent rounds up.

        // Calculate the factor by which the invariant will increase after minting bptAmountOut.
        uint256 invariantRatio = (bptTotalSupply + bptAmountOut).divUp(bptTotalSupply);
        // Cannot exceed maximum invariant ratio.
        if (invariantRatio > _MAX_INVARIANT_RATIO) {
            revert MaxOutBptForTokenIn();
        }

        // Calculate by how much the token balance has to increase to match the invariantRatio.
        uint256 balanceRatio = invariantRatio.powUp(FixedPoint.ONE.divUp(normalizedWeight));

        // Because the base is larger than one (and the power rounds up), the power should always be larger than one, so
        // the following subtraction should never revert.
        uint256 amountInWithoutFee = balance.mulUp(balanceRatio - FixedPoint.ONE);

        // We can now compute how much extra balance is being deposited and used in virtual swaps, and charge swap fees
        // accordingly. Regarding rounding, a conflict of interests arises – the less the `taxableAmount`, the larger
        // the `nonTaxableAmount`; we prioritize maximizing the latter.
        uint256 taxableAmount = amountInWithoutFee.mulDown(normalizedWeight.complement());
        uint256 nonTaxableAmount = amountInWithoutFee - taxableAmount;
        uint256 taxableAmountPlusFees = taxableAmount.divUp(swapFeePercentage.complement());

        return nonTaxableAmount + taxableAmountPlusFees;
    }

    function computeBptInGivenExactTokensOut(
        uint256[] memory balances,
        uint256[] memory normalizedWeights,
        uint256[] memory amountsOut,
        uint256 bptTotalSupply,
        uint256 swapFeePercentage
    ) internal pure returns (uint256) {
        // BPT in, so we round up overall.

        uint256[] memory balanceRatiosWithoutFee = new uint256[](amountsOut.length);
        uint256 invariantRatioWithoutFees = 0;
        for (uint256 i = 0; i < balances.length; ++i) {
            // Round down to ultimately reduce the ratios without fees,
            // which will be used later when calculating the `nonTaxableAmount` for each token.
            balanceRatiosWithoutFee[i] = (balances[i] - amountsOut[i]).divDown(balances[i]);
            invariantRatioWithoutFees = (invariantRatioWithoutFees + balanceRatiosWithoutFee[i]).mulDown(
                normalizedWeights[i]
            );
        }

        uint256 invariantRatio = computeExitExactTokensOutInvariantRatio(
            balances,
            normalizedWeights,
            amountsOut,
            balanceRatiosWithoutFee,
            invariantRatioWithoutFees,
            swapFeePercentage
        );

        // Round up to increase the amount of BPT in.
        return bptTotalSupply.mulUp(invariantRatio.complement());
    }

    function computeBptInGivenExactTokenOut(
        uint256 balance,
        uint256 normalizedWeight,
        uint256 amountOut,
        uint256 bptTotalSupply,
        uint256 swapFeePercentage
    ) internal pure returns (uint256) {
        // BPT in, so we round up overall.

        // Round down to ultimately reduce the ratios without fees,
        // which will be used later when calculating the `nonTaxableAmount` for tokenOut.
        uint256 balanceRatioWithoutFee = (balance - amountOut).divDown(balance);
        // The use of `normalizedWeight.complement()` assumes that the sum of all weights equals FixedPoint.ONE.
        // This may not be the case when weights are stored in a denormalized format or during a gradual weight
        // change due to rounding errors during normalization or interpolation. This will result in a small
        // difference between the output of this function and the equivalent `computeBptInGivenExactTokensOut` call.
        uint256 invariantRatioWithoutFees = balanceRatioWithoutFee.mulDown(normalizedWeight) +
            normalizedWeight.complement();

        // Swap fees are typically charged on 'token in', but there is no 'token in' here, so we apply it to
        // 'token out'. This results in slightly larger price impact.
        uint256 amountOutWithFee;
        if (invariantRatioWithoutFees > balanceRatioWithoutFee) {
            // Round accordingly to ultimately enlarge the `amountOutWithFee`, consequently reducing the
            // `balanceRatio`; we prioritize maximizing the `nonTaxableAmount` over the `taxableAmount`.
            uint256 nonTaxableAmount = balance.mulUp(invariantRatioWithoutFees.complement());
            uint256 taxableAmount = amountOut - nonTaxableAmount;
            uint256 taxableAmountPlusFees = taxableAmount.divUp(swapFeePercentage.complement());

            amountOutWithFee = nonTaxableAmount + taxableAmountPlusFees;
        } else {
            amountOutWithFee = amountOut;

            // If a token's amount out is not being charged a swap fee then it might be zero.
            // In this case, it's clear that the sender should not send any BPT.
            if (amountOutWithFee == 0) {
                return 0;
            }
        }

        // Round down the `balanceRatio` to lower the `invariantRatio`.
        uint256 balanceRatio = (balance - amountOutWithFee).divDown(balance);

        // Round down the `invariantRatio` so that multiplying by its complement increases the BPT in.
        uint256 invariantRatio = balanceRatio.powDown(normalizedWeight);

        // Round up to increase the amount of BPT in.
        return bptTotalSupply.mulUp(invariantRatio.complement());
    }

    /// @dev Intermediate function to avoid stack-too-deep errors.
    function computeExitExactTokensOutInvariantRatio(
        uint256[] memory balances,
        uint256[] memory normalizedWeights,
        uint256[] memory amountsOut,
        uint256[] memory balanceRatiosWithoutFee,
        uint256 invariantRatioWithoutFees,
        uint256 swapFeePercentage
    ) internal pure returns (uint256 invariantRatio) {
        // Swap fees are charged on all tokens that are being removed in a larger proportion than the overall invariant
        // decrease.
        invariantRatio = FixedPoint.ONE;

        for (uint256 i = 0; i < balances.length; ++i) {
            // Swap fees are typically charged on 'token in', but there is no 'token in' here, so we apply it to
            // 'token out'. This results in slightly larger price impact.
            uint256 amountOutWithFee;
            if (invariantRatioWithoutFees > balanceRatiosWithoutFee[i]) {
                // Round accordingly to ultimately enlarge the `amountOutWithFee`, consequently reducing the
                // `balanceRatio`; we prioritize maximizing the `nonTaxableAmount` over the `taxableAmount`.
                uint256 nonTaxableAmount = balances[i].mulUp(invariantRatioWithoutFees.complement());
                uint256 taxableAmount = amountsOut[i] - nonTaxableAmount;
                uint256 taxableAmountPlusFees = taxableAmount.divUp(swapFeePercentage.complement());

                amountOutWithFee = nonTaxableAmount + taxableAmountPlusFees;
            } else {
                amountOutWithFee = amountsOut[i];

                // If a token's amount out is not being charged a swap fee then it might be zero (e.g. when exiting a
                // Pool with only a subset of tokens). In this case, `balanceRatio` will equal `FixedPoint.ONE`, and
                // the `invariantRatio` will not change at all. We therefore skip to the next iteration, avoiding
                // the costly `powDown` call.
                if (amountOutWithFee == 0) {
                    continue;
                }
            }

            // Round down the `balanceRatio` to lower the `invariantRatio`.
            uint256 balanceRatio = (balances[i] - amountOutWithFee).divDown(balances[i]);

            // Round down the `invariantRatio` so that multiplying by its complement increases the BPT in.
            invariantRatio = invariantRatio.mulDown(balanceRatio.powDown(normalizedWeights[i]));
        }
    }

    function computeTokenOutGivenExactBptIn(
        uint256 balance,
        uint256 normalizedWeight,
        uint256 bptAmountIn,
        uint256 bptTotalSupply,
        uint256 swapFeePercentage
    ) internal pure returns (uint256) {
        /*****************************************************************************************
        // exactBPTInForTokenOut                                                                //
        // a = amountOut                                                                        //
        // b = balance                     /      /  ( totalBPT - bptIn )     \    (1 / w)  \   //
        // bptIn = bptAmountIn    a = b * |  1 - | --------------------------  | ^           |  //
        // bpt = totalBPT                  \      \       totalBPT            /             /   //
        // w = weight                                                                           //
        *****************************************************************************************/

        // Token out, so we round down overall.

        // The multiplication rounds down, and the subtrahend (power) rounds up (so the base rounds up too).
        // Because (totalBPT - bptIn) / totalBPT <= 1, the exponent rounds down.

        // Calculate the factor by which the invariant will decrease after burning bptAmountIn.
        uint256 invariantRatio = (bptTotalSupply - bptAmountIn).divUp(bptTotalSupply);
        // Cannot not reach minimum invariant ratio.
        if (invariantRatio < _MIN_INVARIANT_RATIO) {
            revert MinBPTInForTokenOut();
        }

        // Calculate by how much the token balance has to decrease to match invariantRatio.
        uint256 balanceRatio = invariantRatio.powUp(FixedPoint.ONE.divDown(normalizedWeight));

        // Because of rounding up, balanceRatio can be greater than one. Using complement prevents reverts.
        uint256 amountOutWithoutFee = balance.mulDown(balanceRatio.complement());

        // We can now compute how much excess balance is being withdrawn as a result of the virtual swaps, which result
        // in swap fees. Swap fees are typically charged on 'token in', but there is no 'token in' here, so we apply it
        // to 'token out'. This results in slightly larger price impact. Regarding rounding, a conflict of interests
        // arises – the greater the `taxableAmount`, the smaller the `nonTaxableAmount`; we prioritize minimizing
        // the latter.
        uint256 taxableAmount = amountOutWithoutFee.mulUp(normalizedWeight.complement());
        uint256 nonTaxableAmount = amountOutWithoutFee - taxableAmount;
        uint256 taxableAmountMinusFees = taxableAmount.mulDown(swapFeePercentage.complement());

        return nonTaxableAmount + taxableAmountMinusFees;
    }

    /**
     * @dev Calculate the amount of BPT which should be minted when adding a new token to the Pool.
     *
     * Note that normalizedWeight is set so that it corresponds to the desired weight of this token *after* adding it;
     * i.e., for a two token 50:50 pool which we want to turn into a 33:33:33 pool, we use a normalized weight of 33%.
     *
     * @param totalSupply - the total supply of the Pool's BPT
     * @param normalizedWeight - the normalized weight of the token to be added (normalized relative to final weights)
     */
    function computeBptOutAddToken(uint256 totalSupply, uint256 normalizedWeight) internal pure returns (uint256) {
        // The amount of BPT which is equivalent to the token being added may be calculated by the growth in the
        // sum of the token weights, i.e. if we add a token which will make up 50% of the pool then we should receive
        // 50% of the new supply of BPT.

        // The growth in the total weight of the pool can be easily calculated by:
        //
        // weightSumRatio = totalWeight / (totalWeight - newTokenWeight)
        //
        // As we're working with normalized weights `totalWeight` is equal to 1.

        // Rounds result down overall.

        uint256 weightSumRatio = FixedPoint.ONE.divDown(FixedPoint.ONE - normalizedWeight);

        // The amount of BPT to mint is then simply:
        //
        // toMint = totalSupply * (weightSumRatio - 1)

        return totalSupply.mulDown(weightSumRatio - FixedPoint.ONE);
    }
}
