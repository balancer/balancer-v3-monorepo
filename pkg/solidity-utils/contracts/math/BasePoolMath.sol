// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";

import { FixedPoint } from "./FixedPoint.sol";

library BasePoolMath {
    using FixedPoint for uint256;

    /**
     * @dev An add liquidity operation increased the invariant above the limit. This value is determined by each pool
     * type, and depends on the specific math used to compute the price curve.
     *
     * @param invariantRatio The ratio of the new invariant (after an operation) to the old
     * @param maxInvariantRatio The maximum allowed invariant ratio
     */
    error InvariantRatioAboveMax(uint256 invariantRatio, uint256 maxInvariantRatio);

    /**
     * @dev A remove liquidity operation decreased the invariant below the limit. This value is determined by each pool
     * type, and depends on the specific math used to compute the price curve.
     *
     * @param invariantRatio The ratio of the new invariant (after an operation) to the old
     * @param minInvariantRatio The minimum allowed invariant ratio
     */
    error InvariantRatioBelowMin(uint256 invariantRatio, uint256 minInvariantRatio);

    // For security reasons, to help ensure that for all possible "round trip" paths
    // the caller always receives the same or fewer tokens than supplied,
    // we have chosen the rounding direction to favor the protocol in all cases.

    /**
     * @notice Computes the proportional amounts of tokens to be deposited into the pool.
     * @dev This function computes the amount of each token that needs to be deposited in order to mint a specific
     * amount of pool tokens (BPT). It ensures that the amounts of tokens deposited are proportional to the current
     * pool balances.
     *
     * Calculation: For each token, amountIn = balance * (bptAmountOut / bptTotalSupply)
     * Rounding up is used to ensure that the pool is not underfunded
     *
     * @param balances Array of current token balances in the pool
     * @param bptTotalSupply Total supply of the pool tokens (BPT)
     * @param bptAmountOut The amount of pool tokens that need to be minted
     * @return amountsIn Array of amounts for each token to be deposited
     */
    function computeProportionalAmountsIn(
        uint256[] memory balances,
        uint256 bptTotalSupply,
        uint256 bptAmountOut
    ) internal pure returns (uint256[] memory amountsIn) {
        /************************************************************************************
        // computeProportionalAmountsIn                                                    //
        // (per token)                                                                     //
        // aI = amountIn                   /      bptOut      \                            //
        // b = balance           aI = b * | ----------------- |                            //
        // bptOut = bptAmountOut           \  bptTotalSupply  /                            //
        // bpt = bptTotalSupply                                                            //
        ************************************************************************************/

        // Create a new array to hold the amounts of each token to be deposited.
        amountsIn = new uint256[](balances.length);
        for (uint256 i = 0; i < balances.length; ++i) {
            // Since we multiply and divide we don't need to use FP math.
            // We're calculating amounts in so we round up.
            amountsIn[i] = balances[i].mulDivUp(bptAmountOut, bptTotalSupply);
        }
    }

    /**
     * @notice Computes the proportional amounts of tokens to be withdrawn from the pool.
     * @dev This function computes the amount of each token that will be withdrawn in exchange for burning
     * a specific amount of pool tokens (BPT). It ensures that the amounts of tokens withdrawn are proportional
     * to the current pool balances.
     *
     * Calculation: For each token, amountOut = balance * (bptAmountIn / bptTotalSupply).
     * Rounding down is used to prevent withdrawing more than the pool can afford.
     *
     * @param balances Array of current token balances in the pool
     * @param bptTotalSupply Total supply of the pool tokens (BPT)
     * @param bptAmountIn The amount of pool tokens that will be burned
     * @return amountsOut Array of amounts for each token to be withdrawn
     */
    function computeProportionalAmountsOut(
        uint256[] memory balances,
        uint256 bptTotalSupply,
        uint256 bptAmountIn
    ) internal pure returns (uint256[] memory amountsOut) {
        /**********************************************************************************************
        // computeProportionalAmountsOut                                                             //
        // (per token)                                                                               //
        // aO = tokenAmountOut             /        bptIn         \                                  //
        // b = tokenBalance      a0 = b * | ---------------------  |                                 //
        // bptIn = bptAmountIn             \     bptTotalSupply    /                                 //
        // bpt = bptTotalSupply                                                                      //
        **********************************************************************************************/

        // Create a new array to hold the amounts of each token to be withdrawn.
        amountsOut = new uint256[](balances.length);
        for (uint256 i = 0; i < balances.length; ++i) {
            // Since we multiply and divide we don't need to use FP math.
            // Round down since we're calculating amounts out.
            amountsOut[i] = (balances[i] * bptAmountIn) / bptTotalSupply;
        }
    }

    /**
     * @notice Computes the amount of pool tokens (BPT) to be minted for an unbalanced liquidity addition.
     * @dev This function handles liquidity addition where the proportion of tokens deposited does not match
     * the current pool composition. It considers the current balances, exact amounts of tokens to be added,
     * total supply, and swap fee percentage. The function calculates a new invariant with the added tokens,
     * applying swap fees if necessary, and then calculates the amount of BPT to mint based on the change
     * in the invariant.
     *
     * @param currentBalances Current pool balances, sorted in token registration order
     * @param exactAmounts Array of exact amounts for each token to be added to the pool
     * @param totalSupply The current total supply of the pool tokens (BPT)
     * @param swapFeePercentage The swap fee percentage applied to the transaction
     * @param pool The pool to which we're adding liquidity
     * @return bptAmountOut The amount of pool tokens (BPT) that will be minted as a result of the liquidity addition
     * @return swapFeeAmounts The amount of swap fees charged for each token
     */
    function computeAddLiquidityUnbalanced(
        uint256[] memory currentBalances,
        uint256[] memory exactAmounts,
        uint256 totalSupply,
        uint256 swapFeePercentage,
        IBasePool pool
    ) internal view returns (uint256 bptAmountOut, uint256[] memory swapFeeAmounts) {
        /***********************************************************************
        //                                                                    //
        // s = totalSupply                                 (iFees - iCur)     //
        // b = tokenBalance                  bptOut = s *  --------------     //
        // bptOut = bptAmountOut                                iCur          //
        // iFees = invariantWithFeesApplied                                   //
        // iCur = currentInvariant                                            //
        // iNew = newInvariant                                                //
        ***********************************************************************/

        // Determine the number of tokens in the pool.
        uint256 numTokens = currentBalances.length;

        // Create a new array to hold the updated balances after the addition.
        uint256[] memory newBalances = new uint256[](numTokens);
        // Create a new array to hold the swap fee amount for each token.
        swapFeeAmounts = new uint256[](numTokens);

        // Loop through each token, updating the balance with the added amount.
        for (uint256 i = 0; i < numTokens; ++i) {
            newBalances[i] = currentBalances[i] + exactAmounts[i];
        }

        // Calculate the new invariant ratio by dividing the new invariant by the old invariant.
        uint256 currentInvariant = pool.computeInvariant(currentBalances);
        // Round down to make `taxableAmount` larger below.
        uint256 invariantRatio = pool.computeInvariant(newBalances).divDown(currentInvariant);

        ensureInvariantRatioBelowMaximumBound(pool, invariantRatio);

        // Loop through each token to apply fees if necessary.
        for (uint256 i = 0; i < numTokens; ++i) {
            // Check if the new balance is greater than the equivalent proportional balance.
            // If so, calculate the taxable amount, rounding in favor of the protocol.
            // We round the second term down to subtract less and get a higher `taxableAmount`,
            // which charges higher swap fees. This will lower `newBalances`, which in turn lowers
            // `invariantWithFeesApplied` below.
            uint256 proportionalTokenBalance = invariantRatio.mulDown(currentBalances[i]);
            if (newBalances[i] > proportionalTokenBalance) {
                uint256 taxableAmount;
                unchecked {
                    taxableAmount = newBalances[i] - proportionalTokenBalance;
                }
                // Calculate fee amount
                swapFeeAmounts[i] = taxableAmount.mulUp(swapFeePercentage);

                // Subtract the fee from the new balance.
                // We are essentially imposing swap fees on non-proportional incoming amounts.
                // Note: `swapFeeAmounts` should always be <= `taxableAmount` since `swapFeePercentage` is <= FP(1),
                // but since that's not verifiable within this contract, a checked subtraction is preferred.
                newBalances[i] = newBalances[i] - swapFeeAmounts[i];
            }
        }

        // Calculate the new invariant with fees applied.
        // This invariant should be lower than the original one, so we don't need to check invariant ratio bounds again.
        uint256 invariantWithFeesApplied = pool.computeInvariant(newBalances);

        // Calculate the amount of BPT to mint. This is done by multiplying the
        // total supply with the ratio of the change in invariant.
        // Since we multiply and divide we don't need to use FP math.
        // Round down since we're calculating BPT amount out. `invariantWithFeesApplied` calculated with `newBalances`
        // rounded down, which also contributes to a lower `bptAmountOut`.
        bptAmountOut = (totalSupply * (invariantWithFeesApplied - currentInvariant)) / currentInvariant;
    }

    /**
     * @notice Computes the amount of input token needed to receive an exact amount of pool tokens (BPT) in a
     * single-token liquidity addition.
     * @dev This function is used when a user wants to add liquidity to the pool by specifying the exact amount
     * of pool tokens they want to receive, and the function calculates the corresponding amount of the input token.
     * It considers the current pool balances, total supply, swap fee percentage, and the desired BPT amount.
     *
     * @param currentBalances Array of current token balances in the pool, sorted in token registration order
     * @param tokenInIndex Index of the input token for which the amount needs to be calculated
     * @param exactBptAmountOut Exact amount of pool tokens (BPT) the user wants to receive
     * @param totalSupply The current total supply of the pool tokens (BPT)
     * @param swapFeePercentage The swap fee percentage applied to the taxable amount
     * @param pool The pool to which we're adding liquidity
     * @return amountInWithFee The amount of input token needed, including the swap fee, to receive the exact BPT amount
     * @return swapFeeAmounts The amount of swap fees charged for each token
     */
    function computeAddLiquiditySingleTokenExactOut(
        uint256[] memory currentBalances,
        uint256 tokenInIndex,
        uint256 exactBptAmountOut,
        uint256 totalSupply,
        uint256 swapFeePercentage,
        IBasePool pool
    ) internal view returns (uint256 amountInWithFee, uint256[] memory swapFeeAmounts) {
        // Calculate new supply after minting exactBptAmountOut
        uint256 newSupply = exactBptAmountOut + totalSupply;

        // Calculate the initial amount of the input token needed for the desired amount of BPT out
        // "divUp" leads to a higher "newBalance", which in turn results in a larger "amountIn".
        // This leads to receiving more tokens for the same amount of BPT minted.
        uint256 invariantRatio = newSupply.divUp(totalSupply);
        ensureInvariantRatioBelowMaximumBound(pool, invariantRatio);

        uint256 newBalance = pool.computeBalance(currentBalances, tokenInIndex, invariantRatio);

        // Compute the amount to be deposited into the pool.
        uint256 amountIn = newBalance - currentBalances[tokenInIndex];

        // Calculate the non-taxable amount, which is the new balance proportionate to the BPT minted.
        // Since we multiply and divide we don't need to use FP math.
        // Rounding down makes `taxableAmount` larger, which in turn makes `fee` larger below.
        uint256 nonTaxableBalance = (newSupply * currentBalances[tokenInIndex]) / totalSupply;

        // Calculate the taxable amount, which is the difference
        // between the actual new balance and the non-taxable balance
        uint256 taxableAmount = newBalance - nonTaxableBalance;

        // Calculate the swap fee based on the taxable amount and the swap fee percentage
        uint256 fee = taxableAmount.divUp(swapFeePercentage.complement()) - taxableAmount;

        // Create swap fees amount array and set the single fee we charge
        swapFeeAmounts = new uint256[](currentBalances.length);
        swapFeeAmounts[tokenInIndex] = fee;

        // Return the total amount of input token needed, including the swap fee
        amountInWithFee = amountIn + fee;
    }

    /**
     * @notice Computes the amount of pool tokens to burn to receive exact amount out.
     * @param currentBalances Current pool balances, sorted in token registration order
     * @param tokenOutIndex Index of the token to receive in exchange for pool tokens burned
     * @param exactAmountOut Exact amount of tokens to receive
     * @param totalSupply The current total supply of the pool tokens (BPT)
     * @param swapFeePercentage The swap fee percentage applied to the taxable amount
     * @param pool The pool from which we're removing liquidity
     * @return bptAmountIn Amount of pool tokens to burn
     * @return swapFeeAmounts The amount of swap fees charged for each token
     */
    function computeRemoveLiquiditySingleTokenExactOut(
        uint256[] memory currentBalances,
        uint256 tokenOutIndex,
        uint256 exactAmountOut,
        uint256 totalSupply,
        uint256 swapFeePercentage,
        IBasePool pool
    ) internal view returns (uint256 bptAmountIn, uint256[] memory swapFeeAmounts) {
        // Determine the number of tokens in the pool.
        uint256 numTokens = currentBalances.length;

        // Create a new array to hold the updated balances.
        uint256[] memory newBalances = new uint256[](numTokens);

        // Copy currentBalances to newBalances
        for (uint256 i = 0; i < numTokens; ++i) {
            newBalances[i] = currentBalances[i];
        }

        // Update the balance of tokenOutIndex with exactAmountOut.
        newBalances[tokenOutIndex] = newBalances[tokenOutIndex] - exactAmountOut;

        // Calculate the new invariant using the new balances (after the removal).
        // Calculate the new invariant ratio by dividing the new invariant by the old invariant.
        // Calculate the new proportional balance by multiplying the new invariant ratio by the current balance.
        // Calculate the taxable amount by subtracting the new balance from the equivalent proportional balance.
        uint256 currentInvariant = pool.computeInvariant(currentBalances);
        // We round invariant ratio up (see reason below).
        uint256 invariantRatio = pool.computeInvariant(newBalances).divUp(currentInvariant);

        ensureInvariantRatioAboveMinimumBound(pool, invariantRatio);

        // Taxable amount is proportional to invariant ratio; a larger taxable amount rounds in the Vault's favor.
        uint256 taxableAmount = invariantRatio.mulUp(currentBalances[tokenOutIndex]) - newBalances[tokenOutIndex];

        // Calculate the swap fee based on the taxable amount and the swap fee percentage.
        // Fee is proportional to taxable amount; larger fee rounds in the Vault's favor.
        uint256 fee = taxableAmount.divUp(swapFeePercentage.complement()) - taxableAmount;

        // Update new balances array with a fee
        newBalances[tokenOutIndex] = newBalances[tokenOutIndex] - fee;

        // Calculate the new invariant with fees applied.
        // Larger fee means `invariantWithFeesApplied` goes lower.
        uint256 invariantWithFeesApplied = pool.computeInvariant(newBalances);

        // Create swap fees amount array and set the single fee we charge
        swapFeeAmounts = new uint256[](numTokens);
        swapFeeAmounts[tokenOutIndex] = fee;

        // Calculate the amount of BPT to burn. This is done by multiplying the
        // total supply with the ratio of the change in invariant.
        // Since we multiply and divide we don't need to use FP math.
        // Calculating BPT amount in, so we round up.
        // Finally, lower `invariantWithFeesApplied` makes the subtraction larger, which also helps `bptAmountIn` to be
        // larger since it's in the numerator.
        bptAmountIn = totalSupply.mulDivUp(currentInvariant - invariantWithFeesApplied, currentInvariant);
    }

    /**
     * @notice Computes the amount of a single token to withdraw for a given amount of BPT to burn.
     * @dev It computes the output token amount for an exact input of BPT, considering current balances,
     * total supply, and swap fees.
     *
     * @param currentBalances The current token balances in the pool
     * @param tokenOutIndex The index of the token to be withdrawn
     * @param exactBptAmountIn The exact amount of BPT the user wants to burn
     * @param totalSupply The current total supply of the pool tokens (BPT)
     * @param swapFeePercentage The swap fee percentage applied to the taxable amount
     * @param pool The pool from which we're removing liquidity
     * @return amountOutWithFee The amount of the output token the user receives, accounting for swap fees
     */
    function computeRemoveLiquiditySingleTokenExactIn(
        uint256[] memory currentBalances,
        uint256 tokenOutIndex,
        uint256 exactBptAmountIn,
        uint256 totalSupply,
        uint256 swapFeePercentage,
        IBasePool pool
    ) internal view returns (uint256 amountOutWithFee, uint256[] memory swapFeeAmounts) {
        // Calculate new supply accounting for burning exactBptAmountIn
        uint256 newSupply = totalSupply - exactBptAmountIn;
        uint256 invariantRatio = newSupply.divUp(totalSupply);
        ensureInvariantRatioAboveMinimumBound(pool, invariantRatio);

        // Calculate the new balance of the output token after the BPT burn.
        // "divUp" leads to a higher "newBalance", which in turn results in a lower "amountOut", but also a lower
        // "taxableAmount". Although the former leads to giving less tokens for the same amount of BPT burned,
        // the latter leads to charging less swap fees. In consequence, a conflict of interests arises regarding
        // the rounding of "newBalance"; we prioritize getting a lower "amountOut".
        uint256 newBalance = pool.computeBalance(currentBalances, tokenOutIndex, invariantRatio);

        // Compute the amount to be withdrawn from the pool.
        uint256 amountOut = currentBalances[tokenOutIndex] - newBalance;

        // Calculate the new balance proportionate to the BPT burnt.
        // We round up: higher `newBalanceBeforeTax` makes `taxableAmount` go up, which rounds in the Vault's favor.
        uint256 newBalanceBeforeTax = newSupply.mulDivUp(currentBalances[tokenOutIndex], totalSupply);

        // Compute the taxable amount: the difference between the new proportional and disproportional balances.
        uint256 taxableAmount = newBalanceBeforeTax - newBalance;

        // Calculate the swap fee on the taxable amount.
        uint256 fee = taxableAmount.mulUp(swapFeePercentage);

        // Create swap fees amount array and set the single fee we charge
        swapFeeAmounts = new uint256[](currentBalances.length);
        swapFeeAmounts[tokenOutIndex] = fee;

        // Return the net amount after subtracting the fee.
        amountOutWithFee = amountOut - fee;
    }

    /**
     * @notice Validate the invariant ratio against the maximum bound.
     * @dev This is checked when we're adding liquidity, so the `invariantRatio` > 1.
     * @param pool The pool to which we're adding liquidity
     * @param invariantRatio The ratio of the new invariant (after an operation) to the old
     */
    function ensureInvariantRatioBelowMaximumBound(IBasePool pool, uint256 invariantRatio) internal view {
        uint256 maxInvariantRatio = pool.getMaximumInvariantRatio();
        if (invariantRatio > maxInvariantRatio) {
            revert InvariantRatioAboveMax(invariantRatio, maxInvariantRatio);
        }
    }

    /**
     * @notice Validate the invariant ratio against the maximum bound.
     * @dev This is checked when we're removing liquidity, so the `invariantRatio` < 1.
     * @param pool The pool from which we're removing liquidity
     * @param invariantRatio The ratio of the new invariant (after an operation) to the old
     */
    function ensureInvariantRatioAboveMinimumBound(IBasePool pool, uint256 invariantRatio) internal view {
        uint256 minInvariantRatio = pool.getMinimumInvariantRatio();
        if (invariantRatio < minInvariantRatio) {
            revert InvariantRatioBelowMin(invariantRatio, minInvariantRatio);
        }
    }
}
