// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { FixedPoint } from "./FixedPoint.sol";

library BasePoolMath {
    using FixedPoint for uint256;

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

        // Since we're computing amounts in, we round up overall. This means rounding up on both the
        // multiplication and division.

        uint256 bptRatio = bptAmountOut.divUp(bptTotalSupply);

        amountsIn = new uint256[](balances.length);
        for (uint256 i = 0; i < balances.length; i++) {
            amountsIn[i] = balances[i].mulUp(bptRatio);
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
     * @param balances Array of current token balances in the pool.
     * @param bptTotalSupply Total supply of the pool tokens (BPT).
     * @param bptAmountIn The amount of pool tokens that will be burned.
     * @return amountsOut Array of amounts for each token to be withdrawn.
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

        // Since we're computing an amount out, we round down overall. This means rounding down on both the
        // multiplication and division.

        uint256 bptRatio = bptAmountIn.divDown(bptTotalSupply);

        amountsOut = new uint256[](balances.length);
        for (uint256 i = 0; i < balances.length; i++) {
            amountsOut[i] = balances[i].mulDown(bptRatio);
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
     * @param currentBalances Current pool balances, in token registration order
     * @param exactAmounts Array of exact amounts for each token to be added to the pool
     * @param totalSupply Current total supply of the pool tokens (BPT)
     * @param swapFeePercentage The swap fee percentage applied to the transaction
     * @param computeInvariant A function pointer to the invariant calculation function
     * @return bptAmountOut The amount of pool tokens (BPT) that will be minted as a result of the liquidity addition
     * @return swapFeeAmounts The amount of swap fees charged for each token
     */
    function computeAddLiquidityUnbalanced(
        uint256[] memory currentBalances,
        uint256[] memory exactAmounts,
        uint256 totalSupply,
        uint256 swapFeePercentage,
        function(uint256[] memory) external view returns (uint256) computeInvariant
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
        for (uint256 index = 0; index < currentBalances.length; index++) {
            newBalances[index] = currentBalances[index] + exactAmounts[index];
        }

        // Calculate the invariant using the current balances (before the addition).
        uint256 currentInvariant = computeInvariant(currentBalances);

        // Calculate the new invariant using the new balances (after the addition).
        uint256 newInvariant = computeInvariant(newBalances);

        // Calculate the new invariant ratio by dividing the new invariant by the old invariant.
        uint256 invariantRatio = newInvariant.divDown(currentInvariant);

        // Loop through each token to apply fees if necessary.
        for (uint256 index = 0; index < currentBalances.length; index++) {
            // Check if the new balance is greater than the proportional balance.
            // If so, calculate the taxable amount.
            if (newBalances[index] > invariantRatio.mulUp(currentBalances[index])) {
                uint256 taxableAmount = newBalances[index] - invariantRatio.mulUp(currentBalances[index]);
                // Calculate fee amount
                swapFeeAmounts[index] = taxableAmount.mulUp(swapFeePercentage);
                // Subtract the fee from the new balance.
                // We are essentially imposing swap fees on non-proportional incoming amounts.
                newBalances[index] = newBalances[index] - swapFeeAmounts[index];
            }
        }

        // Calculate the new invariant with fees applied.
        uint256 invariantWithFeesApplied = computeInvariant(newBalances);

        // Calculate the amount of BPT to mint. This is done by multiplying the
        // total supply with the ratio of the change in invariant.
        // mulDown/divDown minize amount of pool tokens to mint.
        bptAmountOut = totalSupply.mulDown((invariantWithFeesApplied - currentInvariant).divDown(currentInvariant));
    }

    /**
     * @notice Computes the amount of input token needed to receive an exact amount of pool tokens (BPT) in a
     * single-token liquidity addition.
     * @dev This function is used when a user wants to add liquidity to the pool by specifying the exact amount
     * of pool tokens they want to receive, and the function calculates the corresponding amount of the input token.
     * It considers the current pool balances, total supply, swap fee percentage, and the desired BPT amount.
     *
     * @param currentBalances Array of current token balances in the pool, in token registration order
     * @param tokenInIndex Index of the input token for which the amount needs to be calculated
     * @param exactBptAmountOut Exact amount of pool tokens (BPT) the user wants to receive
     * @param totalSupply Current total supply of the pool tokens (BPT)
     * @param swapFeePercentage The swap fee percentage applied to the taxable amount
     * @param computeBalance A function pointer to the balance calculation function
     * @return amountInWithFee The amount of input token needed, including the swap fee, to receive the exact BPT amount
     * @return swapFeeAmounts The amount of swap fees charged for each token
     */
    function computeAddLiquiditySingleTokenExactOut(
        uint256[] memory currentBalances,
        uint256 tokenInIndex,
        uint256 exactBptAmountOut,
        uint256 totalSupply,
        uint256 swapFeePercentage,
        function(uint256[] memory, uint256, uint256) external view returns (uint256) computeBalance
    ) internal view returns (uint256 amountInWithFee, uint256[] memory swapFeeAmounts) {
        // Calculate new supply after minting exactBptAmountOut
        uint256 newSupply = exactBptAmountOut + totalSupply;
        // Calculate the initial amount of the input token needed for the desired amount of BPT out
        // "divUp" leads to a higher "newBalance," which in turn results in a larger "amountIn."
        // This leads to receiving more tokens for the same amount of BTP minted.
        uint256 newBalance = computeBalance(currentBalances, tokenInIndex, newSupply.divUp(totalSupply));
        uint256 amountIn = newBalance - currentBalances[tokenInIndex];

        // Calculate the taxable amount, which is the difference
        // between the actual amount in and the non-taxable balance
        uint256 nonTaxableBalance = newSupply.mulUp(currentBalances[tokenInIndex]).divDown(totalSupply);

        uint256 taxableAmount = (amountIn + currentBalances[tokenInIndex]) - nonTaxableBalance;

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
     * @param currentBalances Current pool balances, in token registration order
     * @param tokenOutIndex Index of the token to receive in exchange for pool tokens burned
     * @param exactAmountOut Exact amount of tokens to receive
     * @param totalSupply Current total supply of the pool tokens (BPT)
     * @param swapFeePercentage The swap fee percentage applied to the taxable amount
     * @return bptAmountIn Amount of pool tokens to burn
     * @return swapFeeAmounts The amount of swap fees charged for each token
     */
    function computeRemoveLiquiditySingleTokenExactOut(
        uint256[] memory currentBalances,
        uint256 tokenOutIndex,
        uint256 exactAmountOut,
        uint256 totalSupply,
        uint256 swapFeePercentage,
        function(uint256[] memory) external view returns (uint256) computeInvariant
    ) internal view returns (uint256 bptAmountIn, uint256[] memory swapFeeAmounts) {
        // Determine the number of tokens in the pool.
        uint256 numTokens = currentBalances.length;

        // Create a new array to hold the updated balances.
        uint256[] memory newBalances = new uint256[](numTokens);

        // Copy currentBalances to newBalances
        // TODO: Optimize with assembly
        for (uint256 index = 0; index < currentBalances.length; index++) {
            newBalances[index] = currentBalances[index];
        }
        // Update the balance of tokenOutIndex with exactAmountOut.
        newBalances[tokenOutIndex] = newBalances[tokenOutIndex] - exactAmountOut;

        // Calculate the invariant using the current balances.
        uint256 currentInvariant = computeInvariant(currentBalances);

        // Calculate the new invariant ratio by dividing the new invariant by the current invariant.
        // Calculate the taxable amount by subtracting the new balance from the equivalent proportional balance.
        uint256 taxableAmount = computeInvariant(newBalances).divUp(currentInvariant).mulUp(
            currentBalances[tokenOutIndex]
        ) - newBalances[tokenOutIndex];

        uint256 fee = taxableAmount.divUp(swapFeePercentage.complement()) - taxableAmount;

        // Update new balances array with a fee
        newBalances[tokenOutIndex] = newBalances[tokenOutIndex] - fee;

        // Calculate the new invariant with fees applied.
        uint256 invariantWithFeesApplied = computeInvariant(newBalances);

        // Create swap fees amount array and set the single fee we charge
        swapFeeAmounts = new uint256[](numTokens);
        swapFeeAmounts[tokenOutIndex] = fee;

        // mulUp/divDown maximize the amount of tokens burned for the security reasons
        bptAmountIn = totalSupply.mulUp(currentInvariant - invariantWithFeesApplied).divDown(currentInvariant);
    }

    /**
     * @notice Computes the amount of a single token to withdraw for a given amount of BPT to burn.
     * @dev It computes the output token amount for an exact input of BPT, considering current balances,
     * total supply, and swap fees.
     *
     * @param currentBalances The current token balances in the pool.
     * @param tokenOutIndex The index of the token to be withdrawn.
     * @param exactBptAmountIn The exact amount of BPT the user wants to burn.
     * @param totalSupply The total supply of BPT in the pool.
     * @param swapFeePercentage The swap fee percentage applied to the taxable amount.
     * @param computeBalance A function pointer to the balance calculation function.
     * @return amountOutWithFee The amount of the output token the user receives, accounting for swap fees.
     */
    function computeRemoveLiquiditySingleTokenExactIn(
        uint256[] memory currentBalances,
        uint256 tokenOutIndex,
        uint256 exactBptAmountIn,
        uint256 totalSupply,
        uint256 swapFeePercentage,
        function(uint256[] memory, uint256, uint256) external view returns (uint256) computeBalance
    ) internal view returns (uint256 amountOutWithFee, uint256[] memory swapFeeAmounts) {
        // Calculate new supply accounting for burning exactBptAmountIn
        uint256 newSupply = totalSupply - exactBptAmountIn;
        // Calculate the new balance of the output token after the BPT burn.
        // "divUp" leads to a higher "newBalance," which in turn results in a lower "amountOut."
        // This leads to giving less tokens for the same amount of BTP burned.
        uint256 newBalance = computeBalance(currentBalances, tokenOutIndex, newSupply.divUp(totalSupply));

        // Compute the amount to be withdrawn from the pool.
        uint256 amountOut = currentBalances[tokenOutIndex] - newBalance;

        // Calculate the non-taxable balance proportionate to the BPT burnt.
        uint256 nonTaxableBalance = newSupply.mulUp(currentBalances[tokenOutIndex]).divDown(totalSupply);

        // Compute the taxable amount: the difference between the non-taxable balance and actual withdrawal.
        uint256 taxableAmount = nonTaxableBalance - newBalance;

        // Calculate the swap fee on the taxable amount.
        uint256 fee = taxableAmount.mulUp(swapFeePercentage);

        // Create swap fees amount array and set the single fee we charge
        swapFeeAmounts = new uint256[](currentBalances.length);
        swapFeeAmounts[tokenOutIndex] = fee;

        // Return the net amount after subtracting the fee.
        amountOutWithFee = amountOut - fee;
    }
}
