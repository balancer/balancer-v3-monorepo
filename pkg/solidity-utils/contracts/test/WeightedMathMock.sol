// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "../math/WeightedMath.sol";

contract WeightedMathMock {
    function computeInvariant(
        uint256[] memory normalizedWeights,
        uint256[] memory balances
    ) external pure returns (uint256) {
        return WeightedMath.computeInvariant(normalizedWeights, balances);
    }

    function computeOutGivenExactIn(
        uint256 balanceIn,
        uint256 weightIn,
        uint256 balanceOut,
        uint256 weightOut,
        uint256 amountIn
    ) external pure returns (uint256) {
        return WeightedMath.computeOutGivenExactIn(balanceIn, weightIn, balanceOut, weightOut, amountIn);
    }

    function computeInGivenExactOut(
        uint256 balanceIn,
        uint256 weightIn,
        uint256 balanceOut,
        uint256 weightOut,
        uint256 amountOut
    ) external pure returns (uint256) {
        return WeightedMath.computeInGivenExactOut(balanceIn, weightIn, balanceOut, weightOut, amountOut);
    }

    function computeBptOutGivenExactTokensIn(
        uint256[] memory balances,
        uint256[] memory normalizedWeights,
        uint256[] memory amountsIn,
        uint256 bptTotalSupply,
        uint256 swapFeePercentage
    ) external pure returns (uint256) {
        return
            WeightedMath.computeBptOutGivenExactTokensIn(
                balances,
                normalizedWeights,
                amountsIn,
                bptTotalSupply,
                swapFeePercentage
            );
    }

    function computeBptOutGivenExactTokenIn(
        uint256 balance,
        uint256 normalizedWeight,
        uint256 amountIn,
        uint256 bptTotalSupply,
        uint256 swapFeePercentage
    ) external pure returns (uint256) {
        return
            WeightedMath.computeBptOutGivenExactTokenIn(
                balance,
                normalizedWeight,
                amountIn,
                bptTotalSupply,
                swapFeePercentage
            );
    }

    function computeTokenInGivenExactBptOut(
        uint256 balance,
        uint256 normalizedWeight,
        uint256 bptAmountOut,
        uint256 bptTotalSupply,
        uint256 swapFeePercentage
    ) external pure returns (uint256) {
        return
            WeightedMath.computeTokenInGivenExactBptOut(
                balance,
                normalizedWeight,
                bptAmountOut,
                bptTotalSupply,
                swapFeePercentage
            );
    }

    function computeBptInGivenExactTokensOut(
        uint256[] memory balances,
        uint256[] memory normalizedWeights,
        uint256[] memory amountsOut,
        uint256 bptTotalSupply,
        uint256 swapFeePercentage
    ) external pure returns (uint256) {
        return
            WeightedMath.computeBptInGivenExactTokensOut(
                balances,
                normalizedWeights,
                amountsOut,
                bptTotalSupply,
                swapFeePercentage
            );
    }

    function computeBptInGivenExactTokenOut(
        uint256 balance,
        uint256 normalizedWeight,
        uint256 amountOut,
        uint256 bptTotalSupply,
        uint256 swapFeePercentage
    ) external pure returns (uint256) {
        return
            WeightedMath.computeBptInGivenExactTokenOut(
                balance,
                normalizedWeight,
                amountOut,
                bptTotalSupply,
                swapFeePercentage
            );
    }

    function computeTokenOutGivenExactBptIn(
        uint256 balance,
        uint256 normalizedWeight,
        uint256 bptAmountIn,
        uint256 bptTotalSupply,
        uint256 swapFeePercentage
    ) external pure returns (uint256) {
        return
            WeightedMath.computeTokenOutGivenExactBptIn(
                balance,
                normalizedWeight,
                bptAmountIn,
                bptTotalSupply,
                swapFeePercentage
            );
    }

    function computeBptOutAddToken(uint256 totalSupply, uint256 normalizedWeight) external pure returns (uint256) {
        return WeightedMath.computeBptOutAddToken(totalSupply, normalizedWeight);
    }
}
