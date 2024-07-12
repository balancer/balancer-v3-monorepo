// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "../math/FixedPoint.sol";
import "../math/WeightedMath.sol";
import "../math/BasePoolMath.sol";

contract BasePoolMathMock {
    using FixedPoint for uint256;

    function getWeights(uint256[] memory balances) public pure returns (uint256[] memory weights) {
        weights = new uint256[](balances.length);

        for (uint256 i = 0; i < balances.length; i++) {
            weights[i] = FixedPoint.ONE.divDown(balances.length);
        }

        return weights;
    }

    function computeInvariantMock(uint256[] memory balances) public pure returns (uint256 invariant) {
        return WeightedMath.computeInvariant(getWeights(balances), balances);
    }

    function computeBalanceMock(
        uint256[] memory balances,
        uint256 tokenInIndex,
        uint256 invariantRatio
    ) public pure returns (uint256 newBalance) {
        return
            WeightedMath.computeBalanceOutGivenInvariant(
                balances[tokenInIndex],
                getWeights(balances)[tokenInIndex],
                invariantRatio
            );
    }

    function computeProportionalAmountsIn(
        uint256[] memory balances,
        uint256 bptTotalSupply,
        uint256 bptAmountOut
    ) external pure returns (uint256[] memory) {
        return BasePoolMath.computeProportionalAmountsIn(balances, bptTotalSupply, bptAmountOut);
    }

    function computeProportionalAmountsOut(
        uint256[] memory balances,
        uint256 bptTotalSupply,
        uint256 bptAmountIn
    ) external pure returns (uint256[] memory) {
        return BasePoolMath.computeProportionalAmountsOut(balances, bptTotalSupply, bptAmountIn);
    }

    function computeAddLiquidityUnbalanced(
        uint256[] memory currentBalances,
        uint256[] memory exactAmounts,
        uint256 totalSupply,
        uint256 swapFeePercentage
    ) external view returns (uint256 bptAmountOut, uint256[] memory swapFeeAmounts) {
        return
            BasePoolMath.computeAddLiquidityUnbalanced(
                currentBalances,
                exactAmounts,
                totalSupply,
                swapFeePercentage,
                this.computeInvariantMock
            );
    }

    function computeAddLiquiditySingleTokenExactOut(
        uint256[] memory currentBalances,
        uint256 tokenInIndex,
        uint256 exactBptAmountOut,
        uint256 totalSupply,
        uint256 swapFeePercentage
    ) external view returns (uint256 amountInWithFee, uint256[] memory swapFeeAmounts) {
        return
            BasePoolMath.computeAddLiquiditySingleTokenExactOut(
                currentBalances,
                tokenInIndex,
                exactBptAmountOut,
                totalSupply,
                swapFeePercentage,
                this.computeBalanceMock
            );
    }

    function computeRemoveLiquiditySingleTokenExactOut(
        uint256[] memory currentBalances,
        uint256 tokenOutIndex,
        uint256 exactAmountOut,
        uint256 totalSupply,
        uint256 swapFeePercentage
    ) external view returns (uint256 bptAmountIn, uint256[] memory swapFeeAmounts) {
        return
            BasePoolMath.computeRemoveLiquiditySingleTokenExactOut(
                currentBalances,
                tokenOutIndex,
                exactAmountOut,
                totalSupply,
                swapFeePercentage,
                this.computeInvariantMock
            );
    }

    function computeRemoveLiquiditySingleTokenExactIn(
        uint256[] memory currentBalances,
        uint256 tokenOutIndex,
        uint256 exactBptAmountIn,
        uint256 totalSupply,
        uint256 swapFeePercentage
    ) external returns (uint256 amountOutWithFee, uint256[] memory swapFeeAmounts) {
        return
            BasePoolMath.computeRemoveLiquiditySingleTokenExactIn(
                currentBalances,
                tokenOutIndex,
                exactBptAmountIn,
                totalSupply,
                swapFeePercentage,
                this.computeBalanceMock
            );
    }
}
