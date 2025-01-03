// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IRouter.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { CallAndRevert } from "./CallAndRevert.sol";

contract PriceImpactHelper is CallAndRevert {
    using FixedPoint for uint256;
    using SafeCast for *;

    IVault internal immutable _vault;
    IRouter internal immutable _router;

    constructor(IVault vault, IRouter router) {
        _vault = vault;
        _router = router;
    }

    /*******************************************************************************
                                Price Impact
    *******************************************************************************/

    function calculateAddLiquidityUnbalancedPriceImpact(
        address pool,
        uint256[] memory exactAmountsIn,
        address sender
    ) external returns (uint256 priceImpact) {
        uint256 bptAmountOut = _queryAddLiquidityUnbalanced(pool, exactAmountsIn, sender);
        uint256[] memory proportionalAmountsOut = _queryRemoveLiquidityProportional(pool, bptAmountOut, sender);

        // get deltas between exactAmountsIn and proportionalAmountsOut
        int256[] memory deltas = new int256[](exactAmountsIn.length);
        for (uint256 i = 0; i < exactAmountsIn.length; i++) {
            deltas[i] = proportionalAmountsOut[i].toInt256() - exactAmountsIn[i].toInt256();
        }

        // query add liquidity for each delta, so we know how unbalanced each amount in is in terms of BPT
        int256[] memory deltaBPTs = new int256[](exactAmountsIn.length);
        for (uint256 i = 0; i < exactAmountsIn.length; i++) {
            deltaBPTs[i] = _queryAddLiquidityUnbalancedForTokenDeltas(pool, i, deltas, sender);
        }

        // zero out deltas leaving only a remaining delta within a single token
        uint256 remainingDeltaIndex = _zeroOutDeltas(pool, deltas, deltaBPTs, sender);

        // calculate price impact ABA with remaining delta and its respective exactAmountIn
        // remaining delta is always negative, so by multiplying by -1 we get a positive number
        uint256 delta = (-deltas[remainingDeltaIndex]).toUint256();
        return delta.divDown(exactAmountsIn[remainingDeltaIndex]) / 2;
    }

    /*******************************************************************************
                                Router Queries
    *******************************************************************************/

    function _queryAddLiquidityUnbalanced(
        address pool,
        uint256[] memory exactAmountsIn,
        address sender
    ) internal returns (uint256) {
        return
            abi.decode(
                _callAndRevert(
                    address(_router),
                    abi.encodeWithSelector(
                        _router.queryAddLiquidityUnbalanced.selector,
                        pool,
                        exactAmountsIn,
                        sender,
                        ""
                    )
                ),
                (uint256)
            );
    }

    function _queryRemoveLiquidityProportional(
        address pool,
        uint256 bptAmountOut,
        address sender
    ) internal returns (uint256[] memory) {
        return
            abi.decode(
                _callAndRevert(
                    address(_router),
                    abi.encodeWithSelector(
                        _router.queryRemoveLiquidityProportional.selector,
                        pool,
                        bptAmountOut,
                        sender,
                        ""
                    )
                ),
                (uint256[])
            );
    }

    function _querySwapSingleTokenExactIn(
        address pool,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 amountIn,
        address sender
    ) internal returns (uint256) {
        return
            abi.decode(
                _callAndRevert(
                    address(_router),
                    abi.encodeWithSelector(
                        _router.querySwapSingleTokenExactIn.selector,
                        pool,
                        tokenIn,
                        tokenOut,
                        amountIn,
                        sender,
                        ""
                    )
                ),
                (uint256)
            );
    }

    function _querySwapSingleTokenExactOut(
        address pool,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 amountOut,
        address sender
    ) internal returns (uint256) {
        return
            abi.decode(
                _callAndRevert(
                    address(_router),
                    abi.encodeWithSelector(
                        _router.querySwapSingleTokenExactOut.selector,
                        pool,
                        tokenIn,
                        tokenOut,
                        amountOut,
                        sender,
                        ""
                    )
                ),
                (uint256)
            );
    }

    /*******************************************************************************
                                    Helpers
    *******************************************************************************/

    function _queryAddLiquidityUnbalancedForTokenDeltas(
        address pool,
        uint256 tokenIndex,
        int256[] memory deltas,
        address sender
    ) internal returns (int256) {
        uint256[] memory zerosWithSingleDelta = new uint256[](deltas.length);
        int256 delta = deltas[tokenIndex];

        if (delta == 0) {
            return 0;
        }

        zerosWithSingleDelta[tokenIndex] = uint256(delta > 0 ? delta : -delta);
        int256 result = int256(_queryAddLiquidityUnbalanced(pool, zerosWithSingleDelta, sender));

        return delta > 0 ? result : -result;
    }

    function _zeroOutDeltas(
        address pool,
        int256[] memory deltas,
        int256[] memory deltaBPTs,
        address sender
    ) internal returns (uint256) {
        // Index of closest from 0 negative number in deltaBPTs array.
        uint256 maxNegativeDeltaIndex = 0;
        IERC20[] memory poolTokens = _vault.getPoolTokens(pool);

        for (uint256 i = 0; i < deltas.length - 1; i++) {
            // get minPositiveDeltaIndex and maxNegativeDeltaIndex
            uint256 minPositiveDeltaIndex = _minPositiveIndex(deltaBPTs);
            maxNegativeDeltaIndex = _maxNegativeIndex(deltaBPTs);

            uint256 givenTokenIndex;
            uint256 resultTokenIndex;
            uint256 resultAmount;

            if (deltaBPTs[minPositiveDeltaIndex] < -deltaBPTs[maxNegativeDeltaIndex]) {
                givenTokenIndex = minPositiveDeltaIndex;
                resultTokenIndex = maxNegativeDeltaIndex;
                resultAmount = _querySwapSingleTokenExactIn(
                    pool,
                    poolTokens[givenTokenIndex],
                    poolTokens[resultTokenIndex],
                    deltas[givenTokenIndex].toUint256(),
                    sender
                );
            } else {
                givenTokenIndex = maxNegativeDeltaIndex;
                resultTokenIndex = minPositiveDeltaIndex;
                resultAmount = _querySwapSingleTokenExactOut(
                    pool,
                    poolTokens[resultTokenIndex],
                    poolTokens[givenTokenIndex],
                    (-deltas[givenTokenIndex]).toUint256(),
                    sender
                );
            }

            // Update deltas and deltaBPTs
            deltas[givenTokenIndex] = 0;
            deltaBPTs[givenTokenIndex] = 0;
            deltas[resultTokenIndex] += resultAmount.toInt256();
            deltaBPTs[resultTokenIndex] = _queryAddLiquidityUnbalancedForTokenDeltas(
                pool,
                resultTokenIndex,
                deltas,
                sender
            );
        }

        return maxNegativeDeltaIndex;
    }

    // returns the index of the smallest positive integer in an array - i.e. [3, 2, -2, -3] returns 1
    function _minPositiveIndex(int256[] memory array) internal pure returns (uint256 index) {
        int256 min = type(int256).max;
        for (uint256 i = 0; i < array.length; i++) {
            if (array[i] > 0 && array[i] < min) {
                min = array[i];
                index = i;
            }
        }
    }

    // returns the index of the biggest negative integer in an array - i.e. [3, 1, -2, -3] returns 2
    function _maxNegativeIndex(int256[] memory array) internal pure returns (uint256 index) {
        int256 max = type(int256).min;
        for (uint256 i = 0; i < array.length; i++) {
            if (array[i] < 0 && array[i] > max) {
                max = array[i];
                index = i;
            }
        }
    }
}
