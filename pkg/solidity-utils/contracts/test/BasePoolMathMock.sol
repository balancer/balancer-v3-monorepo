// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import {
    IUnbalancedLiquidityInvariantRatioBounds
} from "@balancer-labs/v3-interfaces/contracts/vault/IUnbalancedLiquidityInvariantRatioBounds.sol";
import { PoolSwapParams } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import "../math/FixedPoint.sol";
import "../math/WeightedMath.sol";
import "../math/BasePoolMath.sol";

contract BasePoolMathMock is IBasePool {
    using FixedPoint for uint256;

    function computeInvariant(uint256[] memory balances) public pure returns (uint256) {
        // inv = x + y
        uint256 invariant;
        for (uint256 i = 0; i < balances.length; ++i) {
            invariant += balances[i];
        }
        return invariant;
    }

    function computeBalance(
        uint256[] memory balances,
        uint256 tokenInIndex,
        uint256 invariantRatio
    ) external pure returns (uint256 newBalance) {
        // inv = x + y
        uint256 invariant = computeInvariant(balances);
        return (balances[tokenInIndex] + invariant.mulDown(invariantRatio)) - invariant;
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
                IBasePool(address(this))
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
                IBasePool(address(this))
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
                IBasePool(address(this))
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
                IBasePool(address(this))
            );
    }

    function getMinimumInvariantRatio() external pure override returns (uint256) {
        return 0;
    }

    function getMaximumInvariantRatio() external pure override returns (uint256) {
        return 1_000_000 * 1e18;
    }

    function getMinimumSwapFeePercentage() external pure override returns (uint256) {
        return 0;
    }

    function getMaximumSwapFeePercentage() external pure override returns (uint256) {
        return 1e18;
    }

    function onSwap(PoolSwapParams calldata) external pure returns (uint256) {
        revert("Not implemented");
    }
}
