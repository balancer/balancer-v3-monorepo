// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "../math/StableMath.sol";

contract StableMathMock {
    function calculateInvariant(uint256 amp, uint256[] memory balances) external pure returns (uint256) {
        return StableMath.computeInvariant(amp, balances);
    }

    function outGivenExactIn(
        uint256 amp,
        uint256[] memory balances,
        uint256 tokenIndexIn,
        uint256 tokenIndexOut,
        uint256 tokenAmountIn
    ) external pure returns (uint256) {
        return
            StableMath.computeOutGivenExactIn(
                amp,
                balances,
                tokenIndexIn,
                tokenIndexOut,
                tokenAmountIn,
                StableMath.computeInvariant(amp, balances)
            );
    }

    function inGivenExactOut(
        uint256 amp,
        uint256[] memory balances,
        uint256 tokenIndexIn,
        uint256 tokenIndexOut,
        uint256 tokenAmountOut
    ) external pure returns (uint256) {
        return
            StableMath.computeInGivenExactOut(
                amp,
                balances,
                tokenIndexIn,
                tokenIndexOut,
                tokenAmountOut,
                StableMath.computeInvariant(amp, balances)
            );
    }

    function exactTokensInForBPTOut(
        uint256 amp,
        uint256[] memory balances,
        uint256[] memory amountsIn,
        uint256 bptTotalSupply,
        uint256 currentInvariant,
        uint256 swapFee
    ) external pure returns (uint256) {
        return
            StableMath._calcBptOutGivenExactTokensIn(
                amp,
                balances,
                amountsIn,
                bptTotalSupply,
                currentInvariant,
                swapFee
            );
    }

    function tokenInForExactBPTOut(
        uint256 amp,
        uint256[] memory balances,
        uint256 tokenIndex,
        uint256 bptAmountOut,
        uint256 bptTotalSupply,
        uint256 currentInvariant,
        uint256 swapFee
    ) external pure returns (uint256) {
        return
            StableMath._calcTokenInGivenExactBptOut(
                amp,
                balances,
                tokenIndex,
                bptAmountOut,
                bptTotalSupply,
                currentInvariant,
                swapFee
            );
    }

    function exactBPTInForTokenOut(
        uint256 amp,
        uint256[] memory balances,
        uint256 tokenIndex,
        uint256 bptAmountIn,
        uint256 bptTotalSupply,
        uint256 currentInvariant,
        uint256 swapFee
    ) external pure returns (uint256) {
        return
            StableMath._calcTokenOutGivenExactBptIn(
                amp,
                balances,
                tokenIndex,
                bptAmountIn,
                bptTotalSupply,
                currentInvariant,
                swapFee
            );
    }

    function bptInForExactTokensOut(
        uint256 amp,
        uint256[] memory balances,
        uint256[] memory amountsOut,
        uint256 bptTotalSupply,
        uint256 currentInvariant,
        uint256 swapFee
    ) external pure returns (uint256) {
        return
            StableMath._calcBptInGivenExactTokensOut(
                amp,
                balances,
                amountsOut,
                bptTotalSupply,
                currentInvariant,
                swapFee
            );
    }

    function getTokenBalanceGivenInvariantAndAllOtherBalances(
        uint256 amplificationParameter,
        uint256[] memory balances,
        uint256 currentInvariant,
        uint256 tokenIndex
    ) external pure returns (uint256) {
        return
            StableMath._getTokenBalanceGivenInvariantAndAllOtherBalances(
                amplificationParameter,
                balances,
                currentInvariant,
                tokenIndex
            );
    }
}
