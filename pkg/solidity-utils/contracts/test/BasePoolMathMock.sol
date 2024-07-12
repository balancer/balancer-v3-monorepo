// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "../math/FixedPoint.sol";
import "../math/WeightedMath.sol";
import "../math/BasePoolMath.sol";

contract BasePoolMathMock {
    using FixedPoint for uint256;

    function computeInvariantMock(uint256[] memory balancesLiveScaled18) public view returns (uint256 invariant) {
        // expected to work with 2 tokens only
        invariant = FixedPoint.ONE;
        for (uint256 i = 0; i < balancesLiveScaled18.length; ++i) {
            invariant = invariant.mulDown(balancesLiveScaled18[i]);
        }
        // scale the invariant to 1e18
        invariant = _sqrt(invariant) * 1e9;
    }

    function _sqrt(uint256 x) internal pure returns (uint256 y) {
        uint256 z = (x + 1).divDown(2);
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z).divDown(2);
        }
    }

    function computeBalanceMock(
        uint256[] memory balancesLiveScaled18,
        uint256 tokenInIndex,
        uint256 invariantRatio
    ) public view returns (uint256 newBalance) {
        uint256 otherTokenIndex = tokenInIndex == 0 ? 1 : 0;

        uint256 newInvariant = computeInvariantMock(balancesLiveScaled18).mulDown(invariantRatio);

        newBalance = ((newInvariant * newInvariant).divDown(balancesLiveScaled18[otherTokenIndex]));
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
    ) external returns (uint256 amountInWithFee, uint256[] memory swapFeeAmounts) {
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
