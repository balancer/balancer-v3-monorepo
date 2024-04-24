// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { StableMath } from "../math/StableMath.sol";
import { FixedPoint } from "../math/FixedPoint.sol";

import { RoundingMock } from "./RoundingMock.sol";

contract StableMathMock is RoundingMock {
    using FixedPoint for uint256;

    function computeInvariant(
        uint256 amplificationParameter,
        uint256[] memory balances
    ) external pure returns (uint256) {
        return StableMath.computeInvariant(amplificationParameter, balances);
    }

    function computeOutGivenExactIn(
        uint256 amplificationParameter,
        uint256[] memory balances,
        uint256 tokenIndexIn,
        uint256 tokenIndexOut,
        uint256 tokenAmountIn,
        uint256 invariant
    ) external pure returns (uint256) {
        return
            StableMath.computeOutGivenExactIn(
                amplificationParameter,
                balances,
                tokenIndexIn,
                tokenIndexOut,
                tokenAmountIn,
                invariant
            );
    }

    function computeInGivenExactOut(
        uint256 amplificationParameter,
        uint256[] memory balances,
        uint256 tokenIndexIn,
        uint256 tokenIndexOut,
        uint256 tokenAmountOut,
        uint256 invariant
    ) external pure returns (uint256) {
        return
            StableMath.computeInGivenExactOut(
                amplificationParameter,
                balances,
                tokenIndexIn,
                tokenIndexOut,
                tokenAmountOut,
                invariant
            );
    }

    function computeBptOutGivenExactTokensIn(
        uint256 amp,
        uint256[] memory balances,
        uint256[] memory amountsIn,
        uint256 bptTotalSupply,
        uint256 currentInvariant,
        uint256 swapFeePercentage
    ) external pure returns (uint256) {
        return
            StableMath.computeBptOutGivenExactTokensIn(
                amp,
                balances,
                amountsIn,
                bptTotalSupply,
                currentInvariant,
                swapFeePercentage
            );
    }

    function computeTokenInGivenExactBptOut(
        uint256 amp,
        uint256[] memory balances,
        uint256 tokenIndex,
        uint256 bptAmountOut,
        uint256 bptTotalSupply,
        uint256 currentInvariant,
        uint256 swapFeePercentage
    ) external pure returns (uint256) {
        return
            StableMath.computeTokenInGivenExactBptOut(
                amp,
                balances,
                tokenIndex,
                bptAmountOut,
                bptTotalSupply,
                currentInvariant,
                swapFeePercentage
            );
    }

    function computeBptInGivenExactTokensOut(
        uint256 amp,
        uint256[] memory balances,
        uint256[] memory amountsOut,
        uint256 bptTotalSupply,
        uint256 currentInvariant,
        uint256 swapFeePercentage
    ) external pure returns (uint256) {
        return
            StableMath.computeBptInGivenExactTokensOut(
                amp,
                balances,
                amountsOut,
                bptTotalSupply,
                currentInvariant,
                swapFeePercentage
            );
    }

    function computeTokenOutGivenExactBptIn(
        uint256 amp,
        uint256[] memory balances,
        uint256 tokenIndex,
        uint256 bptAmountIn,
        uint256 bptTotalSupply,
        uint256 currentInvariant,
        uint256 swapFeePercentage
    ) external pure returns (uint256) {
        return
            StableMath.computeTokenOutGivenExactBptIn(
                amp,
                balances,
                tokenIndex,
                bptAmountIn,
                bptTotalSupply,
                currentInvariant,
                swapFeePercentage
            );
    }

    function computeBalance(
        uint256 amplificationParameter,
        uint256[] memory balances,
        uint256 invariant,
        uint256 tokenIndex
    ) external pure returns (uint256) {
        return StableMath.computeBalance(amplificationParameter, balances, invariant, tokenIndex);
    }
}
