// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { BaseECLPSpecificTest } from "./utils/BaseECLPSpecificTest.sol";

/**
 * @notice Fuzz tests asserting that the E-CLP invariant never decreases across a swap.
 * @dev The pool configuration, the price-1 initialization and the invariant readers live in
 * `BaseECLPSpecificTest`. Liquidity, swap amount, swap direction and token decimals are fuzzed here.
 */
contract SwapInvariantECLPSpecificTest is BaseECLPSpecificTest {
    function setUp() public virtual override {
        BaseECLPSpecificTest.setUp();
    }

    function testSwapExactInInvariantNeverDecreases__Fuzz(
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

        // Cap the trade at 10% of the token 0 balance, in both directions. Token 0 is by far the scarcer side here
        // (the pool starts near `beta`), so it is what limits the reachable trade size whichever way the swap goes.
        swapAmountScaled18 = bound(swapAmountScaled18, _MIN_SWAP_SCALED18, balance0Scaled18 / 10);
        uint256 amountInRaw = _toRawAmount(swapAmountScaled18, swap0To1 ? setup.decimals0 : setup.decimals1);
        vm.assume(amountInRaw > 0);

        uint256 invariantBefore = _computeInvariant(setup.pool);

        vm.prank(lp);
        try
            router.swapSingleTokenExactIn(setup.pool, tokenIn, tokenOut, amountInRaw, 0, MAX_UINT256, false, bytes(""))
        {
            // Swap succeeded; fall through to the invariant check.
        } catch {
            // The trade is not reachable for these balances (e.g. it would drain the outgoing token). Reject the run
            // rather than asserting on a state that never changed.
            vm.assume(false);
        }

        uint256 invariantAfter = _computeInvariant(setup.pool);

        assertGe(invariantAfter, invariantBefore, "Invariant decreased on EXACT_IN swap");
    }

    function testSwapExactOutInvariantNeverDecreases__Fuzz(
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

        // Cap the trade at 10% of the token 0 balance, for the same reason as in the EXACT_IN test.
        swapAmountScaled18 = bound(swapAmountScaled18, _MIN_SWAP_SCALED18, balance0Scaled18 / 10);
        uint256 amountOutRaw = _toRawAmount(swapAmountScaled18, swap0To1 ? setup.decimals1 : setup.decimals0);
        vm.assume(amountOutRaw > 0);

        uint256 invariantBefore = _computeInvariant(setup.pool);

        vm.prank(lp);
        try
            router.swapSingleTokenExactOut(
                setup.pool,
                tokenIn,
                tokenOut,
                amountOutRaw,
                MAX_UINT256,
                MAX_UINT256,
                false,
                bytes("")
            )
        {
            // Swap succeeded; fall through to the invariant check.
        } catch {
            vm.assume(false);
        }

        uint256 invariantAfter = _computeInvariant(setup.pool);

        assertGe(invariantAfter, invariantBefore, "Invariant decreased on EXACT_OUT swap");
    }
}
