// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { FixedPoint } from "./FixedPoint.sol";

import "forge-std/console2.sol";

library BasePoolMath {
    using FixedPoint for uint256;

    /**
     *  @notice Calculates the proportional amounts of tokens to be deposited into the pool.
     *  @dev This function computes the amount of each token that needs to be deposited in order to mint a specific amount of pool tokens (BPT).
     *       It ensures that the amounts of tokens deposited are proportional to the current pool balances.
     *       Calculation: For each token, amountIn = balance * (bptAmountOut / bptTotalSupply).
     *       Rounding up is used to ensure that the pool is not underfunded.
     *  @param balances Array of current token balances in the pool.
     *  @param bptTotalSupply Total supply of the pool tokens (BPT).
     *  @param bptAmountOut The amount of pool tokens that need to be minted.
     *  @return amountsIn Array of amounts for each token to be deposited.
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
     *  @notice Calculates the proportional amounts of tokens to be withdrawn from the pool.
     *  @dev This function computes the amount of each token that will be withdrawn in exchange for burning a specific amount of pool tokens (BPT).
     *       It ensures that the amounts of tokens withdrawn are proportional to the current pool balances.
     *       Calculation: For each token, amountOut = balance * (bptAmountIn / bptTotalSupply).
     *       Rounding down is used to prevent withdrawing more than the pool can afford.
     *  @param balances Array of current token balances in the pool.
     *  @param bptTotalSupply Total supply of the pool tokens (BPT).
     *  @param bptAmountIn The amount of pool tokens that will be burned.
     *  @return amountsOut Array of amounts for each token to be withdrawn.
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
     *  @notice Calculates the amount of pool tokens (BPT) to be minted for an unbalanced liquidity addition.
     *  @dev This function handles liquidity addition where the proportion of tokens deposited does not match the current pool composition.
     *       It considers the current balances, exact amounts of tokens to be added, total supply, and swap fee percentage.
     *       The function calculates a new invariant with the added tokens, applying swap fees if necessary, and then calculates the amount of BPT to mint based on the change in the invariant.
     *  @param oldBalances Array of current token balances in the pool before the addition.
     *  @param exactAmounts Array of exact amounts for each token to be added to the pool.
     *  @param totalSupply Current total supply of the pool tokens (BPT).
     *  @param swapFeePercentage The swap fee percentage applied to the transaction.
     *  @param calcInvariant A function pointer to the invariant calculation function.
     *  @return bptAmountOut The amount of pool tokens (BPT) that will be minted as a result of the liquidity addition.
     */
    function computeAddLiquidityUnbalanced(
        uint256[] memory oldBalances,
        uint256[] memory exactAmounts,
        uint256 totalSupply,
        uint256 swapFeePercentage,
        function(uint256[] memory) external view returns (uint256) calcInvariant
    ) external view returns (uint256 bptAmountOut) {
        // Determine the number of tokens in the pool.
        uint256 numTokens = oldBalances.length;

        // Create a new array to hold the updated balances after the addition.
        uint256[] memory newBalances = new uint256[](numTokens);

        // Loop through each token, updating the balance with the added amount.
        for (uint256 index = 0; index < oldBalances.length; index++) {
            newBalances[index] = oldBalances[index] + exactAmounts[index];
        }

        // Calculate the invariant using the old balances (before the addition).
        uint256 oldInvariant = calcInvariant(oldBalances);

        // Calculate the new invariant ratio by dividing the new invariant (calculated with updated balances) by the old invariant.
        uint256 invariantRatio = calcInvariant(newBalances).divDown(oldInvariant);

        // Create an array to hold the new balances after applying fees.
        uint256[] memory newBalancesWithFees = new uint256[](numTokens);

        // Loop through each token to apply fees if necessary.
        for (uint256 index = 0; index < oldBalances.length; index++) {
            // Check if the adjusted balance (after invariant ratio multiplication) is greater than the new balance.
            // If so, calculate the taxable amount.
            if (invariantRatio.mulUp(oldBalances[index]) > newBalances[index]) {
                uint256 taxableAmount = invariantRatio.mulUp(oldBalances[index]) - newBalances[index];
                // Subtract the fee from the new balance.
                // We are essentially imposing swap fees on incoming amounts; however, it is not feasible to levy these fees in any other manner.
                newBalancesWithFees[index] = newBalances[index] - taxableAmount.divUp(swapFeePercentage);
            } else {
                // If no fee is applicable, keep the new balance as is.
                newBalancesWithFees[index] = newBalances[index];
            }
        }

        // Calculate the new invariant with fees applied.
        uint256 newInvariantWithFees = calcInvariant(newBalancesWithFees);

        // Calculate the amount of BPT to mint. This is done by multiplying the total supply with the ratio of the change in invariant.
        // Note: mulDown/divDown is used because the operation involves giving away pool tokens.
        return totalSupply.mulDown((newInvariantWithFees - oldInvariant).divDown(oldInvariant));
    }
}
