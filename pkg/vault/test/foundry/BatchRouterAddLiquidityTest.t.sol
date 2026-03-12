// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "@balancer-labs/v3-interfaces/contracts/vault/BatchRouterTypes.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

/**
 * @notice Test BatchRouter addLiquidityExactOut — addLiquidity as the final (output) step.
 * @dev I n `_addLiquidityExactOut`, the backward ExactOut iteration visits the last array step first, so for a path
 * where addLiquidity is the final step: isFirstStep=true, isLastStep=false. The settlement line:
 *
 *     uint256 stepSettlementAmount = isLastStep ? stepExactAmountOut : amountIn;
 *
 * picks `amountIn` (underlying token units) instead of `stepExactAmountOut` (BPT units) to subtract from BPT tracking.
 * When a swap fee is set on the join pool, amountIn > stepExactAmountOut because the user pays more tokens to cover
 * the fee. tSub(BPT, amountIn) then underflows — BPT tracking only accumulated stepExactAmountOut — and the call
 * reverts.
 *
 * Without a fee, a balanced 50/50 pool coincidentally produces amountIn == stepExactAmountOut, masking the bug.
 * The 1% fee below breaks that equality.
 */
contract BatchRouterAddLiquidityTest is BaseVaultTest {
    using ArrayHelpers for *;

    address internal swapPool; // DAI / WETH
    address internal joinPool; // WETH / USDC  (BPT is the path output)

    uint256 internal constant EXACT_BPT_OUT = 1e18;
    uint256 internal constant JOIN_POOL_SWAP_FEE = 1e16; // 1%

    function setUp() public override {
        super.setUp();

        vm.startPrank(lp);
        (swapPool, ) = _createPool([address(dai), address(weth)].toMemoryArray(), "swapPool");
        _initPool(swapPool, [poolInitAmount, poolInitAmount].toMemoryArray(), 0);

        (joinPool, ) = _createPool([address(usdc), address(weth)].toMemoryArray(), "joinPool");
        _initPool(joinPool, [poolInitAmount, poolInitAmount].toMemoryArray(), 0);
        vm.stopPrank();

        // Non-zero fee ensures amountIn > exactBptOut, exposing the underflow.
        vault.manualSetStaticSwapFeePercentage(joinPool, JOIN_POOL_SWAP_FEE);
    }

    // Path: DAI --[swap DAI→WETH]--> WETH --[addLiquidity WETH→BPT]--> BPT
    function testExactOutSwapThenAddLiquidityFinalStep() public {
        SwapPathExactAmountOut[] memory paths = new SwapPathExactAmountOut[](1);
        paths[0].tokenIn = dai;
        paths[0].exactAmountOut = EXACT_BPT_OUT;
        paths[0].maxAmountIn = type(uint128).max;
        paths[0].steps = new SwapPathStep[](2);

        // Step 0: swap DAI → WETH
        paths[0].steps[0] = SwapPathStep({ pool: swapPool, tokenOut: weth, isBuffer: false });

        // Step 1 (final/output): addLiquidity WETH → BPT[joinPool]
        // tokenOut == pool signals the addLiquidity branch.
        // In the backwards loop this step is visited first:
        //   isFirstStep = (j == steps.length - 1) = true
        //   isLastStep  = (j == 0)                = false
        paths[0].steps[1] = SwapPathStep({ pool: joinPool, tokenOut: IERC20(joinPool), isBuffer: false });

        uint256 bptBefore = IERC20(joinPool).balanceOf(lp);

        vm.prank(lp);
        (uint256[] memory pathAmountsIn, , ) = batchRouter.swapExactOut(paths, type(uint128).max, false, bytes(""));

        assertGe(IERC20(joinPool).balanceOf(lp), bptBefore + EXACT_BPT_OUT, "lp did not receive BPT");
        assertGt(pathAmountsIn[0], 0, "amountIn should be positive");
        assertEq(IERC20(joinPool).balanceOf(address(batchRouter)), 0, "router holds residual BPT");
        assertEq(weth.balanceOf(address(batchRouter)), 0, "router holds residual WETH");
    }
}
