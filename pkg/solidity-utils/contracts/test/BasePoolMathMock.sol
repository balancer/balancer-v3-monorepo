// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "../math/BasePoolMath.sol";

abstract contract BasePoolMathMock {
    function computeInvariant(uint256[] memory balances) public view virtual returns (uint256);

    function computeBalance(
        uint256[] memory balances,
        uint256 tokenInIndex,
        uint256 invariantRatio
    ) external view virtual returns (uint256 newBalance);

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
                this.computeInvariant
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
                this.computeBalance
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
                this.computeInvariant
            );
    }

    function computeRemoveLiquiditySingleTokenExactIn(
        uint256[] memory currentBalances,
        uint256 tokenOutIndex,
        uint256 exactBptAmountIn,
        uint256 totalSupply,
        uint256 swapFeePercentage
    ) external view returns (uint256 amountOutWithFee, uint256[] memory swapFeeAmounts) {
        return
            BasePoolMath.computeRemoveLiquiditySingleTokenExactIn(
                currentBalances,
                tokenOutIndex,
                exactBptAmountIn,
                totalSupply,
                swapFeePercentage,
                this.computeBalance
            );
    }
}
