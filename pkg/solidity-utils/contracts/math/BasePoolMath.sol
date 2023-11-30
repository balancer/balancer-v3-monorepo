// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { FixedPoint } from "./FixedPoint.sol";

library BasePoolMath {
    using FixedPoint for uint256;

    /**
     * @notice Calculates the proportional amounts of tokens to be deposited into the pool.
     * @dev This function computes the amount of each token that needs to be deposited in order to mint a specific amount of pool tokens (BPT)
     *      It ensures that the amounts of tokens deposited are proportional to the current pool balances
     *      Calculation: For each token, amountIn = balance * (bptAmountOut / bptTotalSupply)
     *      Rounding up is used to ensure that the pool is not underfunded
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
     * @notice Calculates the proportional amounts of tokens to be withdrawn from the pool.
     * @dev This function computes the amount of each token that will be withdrawn in exchange for burning a specific amount of pool tokens (BPT).
     *      It ensures that the amounts of tokens withdrawn are proportional to the current pool balances.
     *      Calculation: For each token, amountOut = balance * (bptAmountIn / bptTotalSupply).
     *      Rounding down is used to prevent withdrawing more than the pool can afford.
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
     * @notice Calculates the amount of pool tokens (BPT) to be minted for an unbalanced liquidity addition.
     * @dev This function handles liquidity addition where the proportion of tokens deposited does not match the current pool composition
     *      It considers the current balances, exact amounts of tokens to be added, total supply, and swap fee percentage
     *      The function calculates a new invariant with the added tokens, applying swap fees if necessary, and then calculates the amount of BPT to mint based on the change in the invariant
     * @param currentBalances Current pool balances, in the same order as the tokens registered in the pool
     * @param exactAmounts Array of exact amounts for each token to be added to the pool
     * @param totalSupply Current total supply of the pool tokens (BPT)
     * @param swapFeePercentage The swap fee percentage applied to the transaction
     * @param calcInvariant A function pointer to the invariant calculation function
     * @return bptAmountOut The amount of pool tokens (BPT) that will be minted as a result of the liquidity addition
     */
    function computeAddLiquidityUnbalanced(
        uint256[] memory currentBalances,
        uint256[] memory exactAmounts,
        uint256 totalSupply,
        uint256 swapFeePercentage,
        function(uint256[] memory) external view returns (uint256) calcInvariant
    ) external view returns (uint256 bptAmountOut) {
        // Determine the number of tokens in the pool.
        uint256 numTokens = currentBalances.length;

        // Create a new array to hold the updated balances after the addition.
        uint256[] memory newBalances = new uint256[](numTokens);

        // Loop through each token, updating the balance with the added amount.
        for (uint256 index = 0; index < currentBalances.length; index++) {
            newBalances[index] = currentBalances[index] + exactAmounts[index];
        }

        // Calculate the invariant using the current balances (before the addition).
        uint256 currentInvariant = calcInvariant(currentBalances);

        // Calculate the new invariant ratio by dividing the new invariant (calculated with updated balances) by the old invariant.
        uint256 invariantRatio = calcInvariant(newBalances).divDown(currentInvariant);

        // Loop through each token to apply fees if necessary.
        for (uint256 index = 0; index < currentBalances.length; index++) {
            // Check if the adjusted balance (after invariant ratio multiplication) is greater than the new balance.
            // If so, calculate the taxable amount.
            if (invariantRatio.mulUp(currentBalances[index]) > newBalances[index]) {
                uint256 taxableAmount = invariantRatio.mulUp(currentBalances[index]) - newBalances[index];
                // Subtract the fee from the new balance.
                // We are essentially imposing swap fees on non-proportional incoming amounts.
                newBalances[index] = newBalances[index] - taxableAmount.divUp(swapFeePercentage);
            }
        }

        // Calculate the new invariant with fees applied.
        uint256 newInvariantWithFees = calcInvariant(newBalances);

        // Calculate the amount of BPT to mint. This is done by multiplying the total supply with the ratio of the change in invariant.
        //  mulDown/divDown minize amount of pool tokens to mint.
        return totalSupply.mulDown((newInvariantWithFees - currentInvariant).divDown(currentInvariant));
    }

    /**
     * @notice Calculates the amount of pool tokens to burn to receive exact amount out.
     * @param currentBalances Current pool balances, in the same order as the tokens registered in the pool
     * @param tokenOutIndex Index of the token to receive in exchange for pool tokens burned
     * @param exactAmountOut Exact amount of tokens to receive
     * @param totalSupply Current total supply of the pool tokens (BPT)
     * @param swapFeePercentage The swap fee percentage applied to the taxable amount
     * @return bptAmountIn Amount of pool tokens to burn
     */
    function computeRemoveLiquiditySingleTokenExactOut(
        uint256[] memory currentBalances,
        uint256 tokenOutIndex,
        uint256 exactAmountOut,
        uint256 totalSupply,
        uint256 swapFeePercentage,
        function(uint256[] memory) external view returns (uint256) calcInvariant
    ) external view returns (uint256 bptAmountIn) {
        //tokens_number = len(balances)
        // Determine the number of tokens in the pool.
        uint256 numTokens = currentBalances.length;

        // Create a new array to hold the updated balances.
        uint256[] memory newBalances = new uint256[](numTokens);

        // Loop through each token, updating the balance with the removed amount.
        for (uint256 index = 0; index < currentBalances.length; index++) {
            newBalances[index] = currentBalances[index] - (index == tokenOutIndex ? exactAmountOut : 0);
        }

        // Calculate the invariant using the current balances.
        uint256 currentInvariant = calcInvariant(currentBalances);

        // Calculate the new invariant ratio by dividing the new invariant by the current invariant.
        uint256 invariantRatio = calcInvariant(newBalances).divDown(currentInvariant);

        uint256 taxableAmount = invariantRatio * currentBalances[tokenOutIndex] - newBalances[tokenOutIndex];

        uint256 fee = taxableAmount.divUp(swapFeePercentage.complement()) - taxableAmount;

        // Update new balances array with a fee
        newBalances[tokenOutIndex] = newBalances[tokenOutIndex] - fee;

        // Calculate the new invariant with fees applied.
        uint256 newInvariantWithFees = calcInvariant(newBalances);

        // mulUp/divDown maximize the amount of tokens burned for the security reasons
        return totalSupply.mulUp(currentInvariant - newInvariantWithFees).divDown(currentInvariant);
    }
}
