// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { BaseECLPSpecificTest } from "./utils/BaseECLPSpecificTest.sol";

/**
 * @notice Fuzz tests for value extraction through swap paths on one specific E-CLP configuration.
 * @dev Two properties are covered: a swap immediately undone by the reverse swap must lose the trader roughly two
 * swap fees and never earn anything, and splitting a trade into several smaller swaps must never yield more output
 * than a single swap of the same total size from the same starting state.
 *
 * The pool configuration, the price-1 initialization and the invariant readers live in `BaseECLPSpecificTest`.
 * Liquidity, trade size, direction and both token decimals are fuzzed here.
 */
contract SwapRoundTripECLPSpecificTest is BaseECLPSpecificTest {
    using FixedPoint for uint256;

    /**
     * @dev Upper bound on the relative loss of a do-undo round trip, in 18-decimal fixed point.
     * Each leg charges `_SWAP_FEE_PERCENTAGE` on its input, so a round trip of `a` returns about
     * `a - fee * a - fee * b * p`, where `b` is the intermediate amount and `p` the price at which it is valued.
     * The whole price interval of this pool is `[0.980392..., 1.000000...]`, so `b * p` can never exceed `a` by more
     * than a hair, and the loss is bounded by ~2 fees. The worst relative loss measured over 10000 fuzz runs was
     * indeed 2 fees to five significant digits, and a bound of exactly `2 * _SWAP_FEE_PERCENTAGE` also passes 10000
     * runs; this constant keeps a 1.5x margin over the theoretical value, which still catches the pool charging half
     * again as much as it should.
     */
    uint256 internal constant _MAX_ROUND_TRIP_LOSS_PERCENTAGE = 3 * _SWAP_FEE_PERCENTAGE;

    uint256 internal constant _MIN_SPLIT_COUNT = 2;
    uint256 internal constant _MAX_SPLIT_COUNT = 10;

    function setUp() public virtual override {
        BaseECLPSpecificTest.setUp();
    }

    /**
     * @notice A swap immediately undone by swapping the whole proceeds back cannot leave the trader better off.
     * @dev Also checks that the loss is not absurdly large (the pool overcharging would be as much of a bug as it
     * undercharging), and that the invariant did not decrease across the pair of swaps.
     *
     * @param balance0Scaled18 Initial liquidity of the token at index 0, as an 18-decimal value
     * @param swapAmountScaled18 Size of the first leg, as an 18-decimal value
     * @param swap0To1 Whether the first leg sells token 0 for token 1
     * @param decimalsA Decimals of the first deployed token
     * @param decimalsB Decimals of the second deployed token
     */
    function testSwapRoundTripCannotProfit__Fuzz(
        uint256 balance0Scaled18,
        uint256 swapAmountScaled18,
        bool swap0To1,
        uint8 decimalsA,
        uint8 decimalsB
    ) public {
        decimalsA = uint8(bound(decimalsA, _MIN_DECIMALS, _MAX_DECIMALS));
        decimalsB = uint8(bound(decimalsB, _MIN_DECIMALS, _MAX_DECIMALS));
        balance0Scaled18 = bound(balance0Scaled18, _MIN_BALANCE0_SCALED18, _MAX_BALANCE0_SCALED18);

        PoolSetup memory setup = _createAndInitPoolAtPriceOne(decimalsA, decimalsB, balance0Scaled18);

        _assertSpotPriceIsOne(setup.pool);

        (IERC20 tokenIn, IERC20 tokenOut) = swap0To1 ? (setup.token0, setup.token1) : (setup.token1, setup.token0);
        (uint8 decimalsIn, uint8 decimalsOut) = swap0To1
            ? (setup.decimals0, setup.decimals1)
            : (setup.decimals1, setup.decimals0);

        // Cap the trade at 10% of the token 0 balance, in both directions. Token 0 is by far the scarcer side here
        // (the pool starts near `beta`), so it is what limits the reachable trade size whichever way the swap goes.
        swapAmountScaled18 = bound(swapAmountScaled18, _MIN_SWAP_SCALED18, balance0Scaled18 / 10);
        uint256 amountInRaw = _toRawAmount(swapAmountScaled18, decimalsIn);

        uint256 invariantBefore = _computeInvariant(setup.pool);
        uint256 balanceInTokenBefore = tokenIn.balanceOf(lp);

        vm.startPrank(lp);
        uint256 amountOutRaw = router.swapSingleTokenExactIn(
            setup.pool,
            tokenIn,
            tokenOut,
            amountInRaw,
            0,
            MAX_UINT256,
            false,
            bytes("")
        );

        // Sell the entire proceeds of the first leg back, undoing the trade.
        router.swapSingleTokenExactIn(setup.pool, tokenOut, tokenIn, amountOutRaw, 0, MAX_UINT256, false, bytes(""));
        vm.stopPrank();

        uint256 balanceInTokenAfter = tokenIn.balanceOf(lp);

        assertLe(balanceInTokenAfter, balanceInTokenBefore, "Round trip was profitable for the trader");

        // Compare in 18-decimal terms so that the bound does not depend on the token decimals.
        uint256 lossScaled18 = (balanceInTokenBefore - balanceInTokenAfter) * (10 ** (18 - decimalsIn));
        uint256 amountInScaled18 = amountInRaw * (10 ** (18 - decimalsIn));

        // The truncation of each leg's output to the raw token decimals can cost the trader up to one raw unit of
        // that token, and both tokens are worth ~1 in 18-decimal terms since the price is pinned to ~1 here.
        uint256 roundingSlackScaled18 = (10 ** (18 - decimalsIn)) + (10 ** (18 - decimalsOut));
        uint256 maxLossScaled18 = amountInScaled18.mulUp(_MAX_ROUND_TRIP_LOSS_PERCENTAGE) + roundingSlackScaled18;

        assertLe(lossScaled18, maxLossScaled18, "Round trip lost more than the expected fees");

        assertGe(_computeInvariant(setup.pool), invariantBefore, "Invariant decreased across the round trip");
    }

    /**
     * @notice Splitting a trade into several swaps must not yield more output than a single swap of the same size.
     * @dev Both branches run from the exact same pool state, restored with a state snapshot, and both consume exactly
     * the same total raw amount in: the split chunks are computed in raw units and the remainder goes into the last
     * chunk.
     *
     * The two branches are allowed to tie: with small trades the split path can match the single swap to the wei,
     * which is expected. What must never happen is the split path coming out ahead by even one wei.
     *
     * @param balance0Scaled18 Initial liquidity of the token at index 0, as an 18-decimal value
     * @param totalAmountScaled18 Total size of the trade, as an 18-decimal value
     * @param splitCount Number of swaps the trade is split into
     * @param swap0To1 Whether the trade sells token 0 for token 1
     * @param decimalsA Decimals of the first deployed token
     * @param decimalsB Decimals of the second deployed token
     */
    function testSplitSwapNeverBeatsSingleSwap__Fuzz(
        uint256 balance0Scaled18,
        uint256 totalAmountScaled18,
        uint256 splitCount,
        bool swap0To1,
        uint8 decimalsA,
        uint8 decimalsB
    ) public {
        decimalsA = uint8(bound(decimalsA, _MIN_DECIMALS, _MAX_DECIMALS));
        decimalsB = uint8(bound(decimalsB, _MIN_DECIMALS, _MAX_DECIMALS));
        balance0Scaled18 = bound(balance0Scaled18, _MIN_BALANCE0_SCALED18, _MAX_BALANCE0_SCALED18);
        splitCount = bound(splitCount, _MIN_SPLIT_COUNT, _MAX_SPLIT_COUNT);

        PoolSetup memory setup = _createAndInitPoolAtPriceOne(decimalsA, decimalsB, balance0Scaled18);

        _assertSpotPriceIsOne(setup.pool);

        (IERC20 tokenIn, IERC20 tokenOut) = swap0To1 ? (setup.token0, setup.token1) : (setup.token1, setup.token0);

        // Same cap as everywhere else in this suite: 10% of the token 0 balance, whichever way the trade goes.
        totalAmountScaled18 = bound(totalAmountScaled18, _MIN_SWAP_SCALED18, balance0Scaled18 / 10);
        uint256 totalAmountRaw = _toRawAmount(totalAmountScaled18, swap0To1 ? setup.decimals0 : setup.decimals1);

        uint256 snapshotId = vm.snapshotState();

        uint256 singleAmountOut = _swapExactIn(setup.pool, tokenIn, tokenOut, totalAmountRaw);

        vm.revertToState(snapshotId);

        uint256 chunkAmountRaw = totalAmountRaw / splitCount;
        uint256 splitAmountOut;
        for (uint256 i = 0; i < splitCount; ++i) {
            // The last chunk absorbs the division remainder, so both branches trade exactly `totalAmountRaw`.
            uint256 amountInRaw = i == splitCount - 1
                ? totalAmountRaw - chunkAmountRaw * (splitCount - 1)
                : chunkAmountRaw;
            splitAmountOut += _swapExactIn(setup.pool, tokenIn, tokenOut, amountInRaw);
        }

        assertLe(splitAmountOut, singleAmountOut, "Splitting the trade yielded more output than a single swap");
    }

    function _swapExactIn(
        address poolToSwap,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 amountInRaw
    ) internal returns (uint256 amountOutRaw) {
        vm.prank(lp);
        amountOutRaw = router.swapSingleTokenExactIn(
            poolToSwap,
            tokenIn,
            tokenOut,
            amountInRaw,
            0,
            MAX_UINT256,
            false,
            bytes("")
        );
    }
}
