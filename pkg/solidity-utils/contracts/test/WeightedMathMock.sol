// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.18;

import "../math/WeightedMath.sol";

contract WeightedMathMock {
    function calculateInvariant(
        uint256[] memory normalizedWeights,
        uint256[] memory balances
    ) external pure returns (uint256) {
        return WeightedMath.calculateInvariant(normalizedWeights, balances);
    }

    function calcOutGivenIn(
        uint256 balanceIn,
        uint256 weightIn,
        uint256 balanceOut,
        uint256 weightOut,
        uint256 amountIn
    ) external pure returns (uint256) {
        return WeightedMath.calcOutGivenIn(balanceIn, weightIn, balanceOut, weightOut, amountIn);
    }

    function calcInGivenOut(
        uint256 balanceIn,
        uint256 weightIn,
        uint256 balanceOut,
        uint256 weightOut,
        uint256 amountOut
    ) external pure returns (uint256) {
        return WeightedMath.calcInGivenOut(balanceIn, weightIn, balanceOut, weightOut, amountOut);
    }

    function calcBptOutGivenExactTokensIn(
        uint256[] memory balances,
        uint256[] memory normalizedWeights,
        uint256[] memory amountsIn,
        uint256 bptTotalSupply,
        uint256 swapFeePercentage
    ) external pure returns (uint256) {
        return
            WeightedMath.calcBptOutGivenExactTokensIn(
                balances,
                normalizedWeights,
                amountsIn,
                bptTotalSupply,
                swapFeePercentage
            );
    }

    function calcBptOutGivenExactTokenIn(
        uint256 balance,
        uint256 normalizedWeight,
        uint256 amountIn,
        uint256 bptTotalSupply,
        uint256 swapFeePercentage
    ) external pure returns (uint256) {
        return
            WeightedMath.calcBptOutGivenExactTokenIn(
                balance,
                normalizedWeight,
                amountIn,
                bptTotalSupply,
                swapFeePercentage
            );
    }

    function calcTokenInGivenExactBptOut(
        uint256 balance,
        uint256 normalizedWeight,
        uint256 bptAmountOut,
        uint256 bptTotalSupply,
        uint256 swapFeePercentage
    ) external pure returns (uint256) {
        return
            WeightedMath.calcTokenInGivenExactBptOut(
                balance,
                normalizedWeight,
                bptAmountOut,
                bptTotalSupply,
                swapFeePercentage
            );
    }

    function calcBptInGivenExactTokensOut(
        uint256[] memory balances,
        uint256[] memory normalizedWeights,
        uint256[] memory amountsOut,
        uint256 bptTotalSupply,
        uint256 swapFeePercentage
    ) external pure returns (uint256) {
        return
            WeightedMath.calcBptInGivenExactTokensOut(
                balances,
                normalizedWeights,
                amountsOut,
                bptTotalSupply,
                swapFeePercentage
            );
    }

    function calcBptInGivenExactTokenOut(
        uint256 balance,
        uint256 normalizedWeight,
        uint256 amountOut,
        uint256 bptTotalSupply,
        uint256 swapFeePercentage
    ) external pure returns (uint256) {
        return
            WeightedMath.calcBptInGivenExactTokenOut(
                balance,
                normalizedWeight,
                amountOut,
                bptTotalSupply,
                swapFeePercentage
            );
    }

    function calcTokenOutGivenExactBptIn(
        uint256 balance,
        uint256 normalizedWeight,
        uint256 bptAmountIn,
        uint256 bptTotalSupply,
        uint256 swapFeePercentage
    ) external pure returns (uint256) {
        return
            WeightedMath.calcTokenOutGivenExactBptIn(
                balance,
                normalizedWeight,
                bptAmountIn,
                bptTotalSupply,
                swapFeePercentage
            );
    }

    function calcBptOutAddToken(
        uint256 totalSupply,
        uint256 normalizedWeight
    ) external pure returns (uint256) {
        return WeightedMath.calcBptOutAddToken(totalSupply, normalizedWeight);
    }
}
