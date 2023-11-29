// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { FixedPoint } from "./FixedPoint.sol";

library BasePoolMath {
    using FixedPoint for uint256;

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

    function computeAddLiquidityUnbalanced(
        uint256[] memory oldBalances,
        uint256[] memory exactAmounts,
        uint256 totalSupply,
        uint256 swapFeePercentage,
        function(uint256[] memory) external view returns (uint256) calcInvariant
    ) external view returns (uint256 bptAmountOut) {
        uint256 numTokens = oldBalances.length;
        uint256[] memory newBalances = new uint256[](numTokens);
        for (uint256 index = 0; index < oldBalances.length; index++) {
            newBalances[index] = oldBalances[index] + exactAmounts[index];
        }
        uint256 oldInvariant = calcInvariant(oldBalances);
        console2.log("oldInvariant:", oldInvariant);
        uint256 invariantRatio = calcInvariant(newBalances).divDown(oldInvariant);
        console2.log("newInvraint:", calcInvariant(newBalances));
        console2.log("invariantRatio:", invariantRatio);
        uint256[] memory newBalancesWithFees = new uint256[](numTokens);
        for (uint256 index = 0; index < oldBalances.length; index++) {
            // mulUp because higher tax is more secure
            if (invariantRatio.mulUp(oldBalances[index]) > newBalances[index]) {
                uint256 taxableAmount = invariantRatio.mulUp(oldBalances[index]) - newBalances[index];
                console2.log("taxableAmount:", taxableAmount);
                newBalancesWithFees[index] = newBalances[index] - taxableAmount.divUp(swapFeePercentage);
            } else {
                newBalancesWithFees[index] = newBalances[index];
            }
        }
        uint256 newInvariantWithFees = calcInvariant(newBalancesWithFees);
        // mulDown/divDown because we are giving away pool tokens
        return totalSupply.mulDown((newInvariantWithFees - oldInvariant).divDown(oldInvariant));
    }
}
