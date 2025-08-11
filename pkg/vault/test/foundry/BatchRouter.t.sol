// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IBatchRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IBatchRouter.sol";
import { ISenderGuard } from "@balancer-labs/v3-interfaces/contracts/vault/ISenderGuard.sol";

import { MOCK_BATCH_ROUTER_VERSION } from "../../contracts/test/BatchRouterMock.sol";
import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract BatchRouterTest is BaseVaultTest {
    uint256 constant MIN_AMOUNT = 1e12;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        // Setup permit2 approvals for BPT operations
        vm.startPrank(alice);
        IERC20(pool).approve(address(permit2), type(uint256).max);
        permit2.approve(address(pool), address(batchRouter), type(uint160).max, type(uint48).max);

        dai.approve(address(permit2), type(uint256).max);
        permit2.approve(address(dai), address(batchRouter), type(uint160).max, type(uint48).max);

        usdc.approve(address(permit2), type(uint256).max);
        permit2.approve(address(usdc), address(batchRouter), type(uint160).max, type(uint48).max);
        vm.stopPrank();
    }

    function testSwapDeadlineExactIn() public {
        IBatchRouter.SwapPathExactAmountIn[] memory paths;

        vm.expectRevert(ISenderGuard.SwapDeadline.selector);
        batchRouter.swapExactIn(paths, block.timestamp - 1, false, bytes(""));
    }

    function testSwapDeadlineExactOut() public {
        IBatchRouter.SwapPathExactAmountOut[] memory paths;

        vm.expectRevert(ISenderGuard.SwapDeadline.selector);
        batchRouter.swapExactOut(paths, block.timestamp - 1, false, bytes(""));
    }

    function testBatchRouterVersion() public view {
        assertEq(batchRouter.version(), MOCK_BATCH_ROUTER_VERSION, "BatchRouter version mismatch");
    }

    function testQuerySingleStepRemove() public {
        // create a swap step and query the batch router, where the first token is the bpt.
        IBatchRouter.SwapPathStep[] memory step = new IBatchRouter.SwapPathStep[](1);
        step[0] = IBatchRouter.SwapPathStep(address(pool), IERC20(address(dai)), false);

        uint256 totalSupply = IERC20(pool).totalSupply();
        uint256 bptAmountIn = 1e18;

        require(bptAmountIn < totalSupply);

        IBatchRouter.SwapPathExactAmountIn memory path = IBatchRouter.SwapPathExactAmountIn(
            IERC20(address(pool)),
            step,
            bptAmountIn,
            0
        );

        IBatchRouter.SwapPathExactAmountIn[] memory paths = new IBatchRouter.SwapPathExactAmountIn[](1);
        paths[0] = path;

        vm.prank(alice, address(0));
        batchRouter.querySwapExactIn(paths, address(0), bytes(""));
    }

    /***************************************************************************
                            BPT Remove Liquidity Operations
    ***************************************************************************/

    function testBPTRemoveLiquidityExactIn() public {
        uint256 bptAmountIn = poolInitAmount / 100; // Small amount to avoid slippage issues

        // Give Alice some BPT first
        vm.startPrank(lp);
        IERC20(pool).transfer(alice, bptAmountIn * 2);
        vm.stopPrank();

        // Create BPT remove liquidity step: BPT -> DAI
        IBatchRouter.SwapPathStep[] memory steps = new IBatchRouter.SwapPathStep[](1);
        steps[0] = IBatchRouter.SwapPathStep({
            pool: address(pool), // pool == stepTokenIn for remove liquidity
            tokenOut: dai,
            isBuffer: false
        });

        IBatchRouter.SwapPathExactAmountIn[] memory paths = new IBatchRouter.SwapPathExactAmountIn[](1);
        paths[0] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: IERC20(address(pool)), // BPT as token in
            steps: steps,
            exactAmountIn: bptAmountIn,
            minAmountOut: 1
        });

        uint256 aliceBptBefore = IERC20(pool).balanceOf(alice);
        uint256 aliceDaiBefore = dai.balanceOf(alice);

        vm.prank(alice);
        (uint256[] memory pathAmountsOut, , ) = batchRouter.swapExactIn(paths, MAX_UINT256, false, bytes(""));

        uint256 aliceBptAfter = IERC20(pool).balanceOf(alice);
        uint256 aliceDaiAfter = dai.balanceOf(alice);

        // Verify BPT was burned and DAI was received
        assertEq(aliceBptAfter, aliceBptBefore - bptAmountIn, "BPT should be burned");
        assertEq(aliceDaiAfter, aliceDaiBefore + pathAmountsOut[0], "DAI should be received");
        assertGt(pathAmountsOut[0], 0, "Should receive some DAI");
    }

    function testBPTRemoveLiquidityExactOut() public {
        uint256 exactDaiOut = poolInitAmount / 1000;
        uint256 maxBptIn = poolInitAmount / 10;

        // Give Alice some BPT
        vm.startPrank(lp);
        IERC20(pool).transfer(alice, maxBptIn);
        vm.stopPrank();

        // Create BPT remove liquidity step: BPT -> DAI (exact out)
        IBatchRouter.SwapPathStep[] memory steps = new IBatchRouter.SwapPathStep[](1);
        steps[0] = IBatchRouter.SwapPathStep({ pool: address(pool), tokenOut: dai, isBuffer: false });

        IBatchRouter.SwapPathExactAmountOut[] memory paths = new IBatchRouter.SwapPathExactAmountOut[](1);
        paths[0] = IBatchRouter.SwapPathExactAmountOut({
            tokenIn: IERC20(address(pool)),
            steps: steps,
            exactAmountOut: exactDaiOut,
            maxAmountIn: maxBptIn
        });

        uint256 aliceBptBefore = IERC20(pool).balanceOf(alice);
        uint256 aliceDaiBefore = dai.balanceOf(alice);

        vm.prank(alice);
        (uint256[] memory pathAmountsIn, , ) = batchRouter.swapExactOut(paths, MAX_UINT256, false, bytes(""));

        uint256 aliceBptAfter = IERC20(pool).balanceOf(alice);
        uint256 aliceDaiAfter = dai.balanceOf(alice);

        // Verify exact DAI amount received and BPT burned
        assertEq(aliceDaiAfter, aliceDaiBefore + exactDaiOut, "Should receive exact DAI amount");
        assertEq(aliceBptAfter, aliceBptBefore - pathAmountsIn[0], "BPT should be burned");
        assertLt(pathAmountsIn[0], maxBptIn, "Should use less than max BPT");
    }

    /***************************************************************************
                            BPT Add Liquidity Operations  
    ***************************************************************************/

    function testBPTAddLiquidityExactIn() public {
        uint256 daiAmountIn = poolInitAmount / 100;

        // Create BPT add liquidity step: DAI -> BPT
        IBatchRouter.SwapPathStep[] memory steps = new IBatchRouter.SwapPathStep[](1);
        steps[0] = IBatchRouter.SwapPathStep({
            pool: address(pool), // pool == step.tokenOut for add liquidity
            tokenOut: IERC20(address(pool)), // BPT as token out
            isBuffer: false
        });

        IBatchRouter.SwapPathExactAmountIn[] memory paths = new IBatchRouter.SwapPathExactAmountIn[](1);
        paths[0] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: dai,
            steps: steps,
            exactAmountIn: daiAmountIn,
            minAmountOut: 1
        });

        uint256 aliceDaiBefore = dai.balanceOf(alice);
        uint256 aliceBptBefore = IERC20(pool).balanceOf(alice);

        vm.prank(alice);
        (uint256[] memory pathAmountsOut, , ) = batchRouter.swapExactIn(paths, MAX_UINT256, false, bytes(""));

        uint256 aliceDaiAfter = dai.balanceOf(alice);
        uint256 aliceBptAfter = IERC20(pool).balanceOf(alice);

        // Verify DAI was spent and BPT was received
        assertEq(aliceDaiAfter, aliceDaiBefore - daiAmountIn, "DAI should be spent");
        assertEq(aliceBptAfter, aliceBptBefore + pathAmountsOut[0], "BPT should be received");
        assertGt(pathAmountsOut[0], 0, "Should receive some BPT");
    }

    function testBPTAddLiquidityExactOut() public {
        uint256 exactBptOut = poolInitAmount / 1000;
        uint256 maxDaiIn = poolInitAmount / 10;

        // Create BPT add liquidity step: DAI -> BPT (exact out)
        IBatchRouter.SwapPathStep[] memory steps = new IBatchRouter.SwapPathStep[](1);
        steps[0] = IBatchRouter.SwapPathStep({ pool: address(pool), tokenOut: IERC20(address(pool)), isBuffer: false });

        IBatchRouter.SwapPathExactAmountOut[] memory paths = new IBatchRouter.SwapPathExactAmountOut[](1);
        paths[0] = IBatchRouter.SwapPathExactAmountOut({
            tokenIn: dai,
            steps: steps,
            exactAmountOut: exactBptOut,
            maxAmountIn: maxDaiIn
        });

        uint256 aliceDaiBefore = dai.balanceOf(alice);
        uint256 aliceBptBefore = IERC20(pool).balanceOf(alice);

        vm.prank(alice);
        (uint256[] memory pathAmountsIn, , ) = batchRouter.swapExactOut(paths, MAX_UINT256, false, bytes(""));

        uint256 aliceDaiAfter = dai.balanceOf(alice);
        uint256 aliceBptAfter = IERC20(pool).balanceOf(alice);

        // Verify exact BPT received and DAI spent
        assertEq(aliceBptAfter, aliceBptBefore + exactBptOut, "Should receive exact BPT amount");
        assertEq(aliceDaiAfter, aliceDaiBefore - pathAmountsIn[0], "DAI should be spent");
        assertLt(pathAmountsIn[0], maxDaiIn, "Should use less than max DAI");
    }

    /***************************************************************************
                              Multi-Step BPT Operations
    ***************************************************************************/

    function testMultiStepBPTRemoveThenAdd() public {
        uint256 bptAmountIn = poolInitAmount / 100;

        // Give Alice some BPT
        vm.startPrank(lp);
        IERC20(pool).transfer(alice, bptAmountIn * 2);
        vm.stopPrank();

        // Multi-step: BPT -> DAI -> BPT (remove then add liquidity)
        IBatchRouter.SwapPathStep[] memory steps = new IBatchRouter.SwapPathStep[](2);
        steps[0] = IBatchRouter.SwapPathStep({
            pool: address(pool), // Remove liquidity: BPT -> DAI
            tokenOut: dai,
            isBuffer: false
        });
        steps[1] = IBatchRouter.SwapPathStep({
            pool: address(pool), // Add liquidity: DAI -> BPT
            tokenOut: IERC20(address(pool)),
            isBuffer: false
        });

        IBatchRouter.SwapPathExactAmountIn[] memory paths = new IBatchRouter.SwapPathExactAmountIn[](1);
        paths[0] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: IERC20(address(pool)),
            steps: steps,
            exactAmountIn: bptAmountIn,
            minAmountOut: 1
        });

        uint256 aliceBptBefore = IERC20(pool).balanceOf(alice);

        vm.prank(alice);
        (uint256[] memory pathAmountsOut, , ) = batchRouter.swapExactIn(paths, MAX_UINT256, false, bytes(""));

        uint256 aliceBptAfter = IERC20(pool).balanceOf(alice);

        // Should end up with different BPT amount due to fees/slippage.
        assertEq(
            aliceBptAfter,
            aliceBptBefore - bptAmountIn + pathAmountsOut[0],
            "BPT balance should update correctly"
        );
    }

    function testIntermediateBPTStep() public {
        uint256 daiAmountIn = poolInitAmount / 100;

        // Multi-step with intermediate BPT: DAI -> BPT -> DAI.
        IBatchRouter.SwapPathStep[] memory steps = new IBatchRouter.SwapPathStep[](2);
        steps[0] = IBatchRouter.SwapPathStep({
            pool: address(pool), // Add liquidity: DAI -> BPT (intermediate)
            tokenOut: IERC20(address(pool)),
            isBuffer: false
        });
        steps[1] = IBatchRouter.SwapPathStep({
            pool: address(pool), // Remove liquidity: BPT -> DAI
            tokenOut: dai,
            isBuffer: false
        });

        IBatchRouter.SwapPathExactAmountIn[] memory paths = new IBatchRouter.SwapPathExactAmountIn[](1);
        paths[0] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: dai,
            steps: steps,
            exactAmountIn: daiAmountIn,
            minAmountOut: 1
        });

        uint256 aliceDaiBefore = dai.balanceOf(alice);

        vm.prank(alice);
        (uint256[] memory pathAmountsOut, , ) = batchRouter.swapExactIn(paths, MAX_UINT256, false, bytes(""));

        uint256 aliceDaiAfter = dai.balanceOf(alice);

        // Should end up with different DAI amount due to fees.
        assertEq(
            aliceDaiAfter,
            aliceDaiBefore - daiAmountIn + pathAmountsOut[0],
            "DAI balance should update correctly"
        );
        assertLt(pathAmountsOut[0], daiAmountIn, "Should get back less DAI due to fees");
    }

    function testBPTRemoveLiquidityIntermediateStepExactOut() public {
        // Simpler approach: just test that intermediate BPT steps use flashloan logic
        // by creating a path where the step is NOT the last step

        uint256 exactUsdcOut = MIN_AMOUNT;
        uint256 maxBptIn = poolInitAmount / 100;

        // Give Alice some BPT
        vm.startPrank(lp);
        IERC20(pool).transfer(alice, maxBptIn);
        vm.stopPrank();

        // Two-step path: BPT -> DAI -> USDC
        // The BPT removal is in the first position (not last), triggering flashloan logic
        IBatchRouter.SwapPathStep[] memory steps = new IBatchRouter.SwapPathStep[](2);
        steps[0] = IBatchRouter.SwapPathStep({
            pool: address(pool), // Remove liquidity: BPT -> DAI (NOT LAST STEP)
            tokenOut: dai,
            isBuffer: false
        });
        steps[1] = IBatchRouter.SwapPathStep({
            pool: pool, // Regular swap: DAI -> USDC
            tokenOut: usdc,
            isBuffer: false
        });

        IBatchRouter.SwapPathExactAmountOut[] memory paths = new IBatchRouter.SwapPathExactAmountOut[](1);
        paths[0] = IBatchRouter.SwapPathExactAmountOut({
            tokenIn: IERC20(address(pool)),
            steps: steps,
            exactAmountOut: exactUsdcOut,
            maxAmountIn: maxBptIn
        });

        vm.prank(alice);
        batchRouter.swapExactOut(paths, MAX_UINT256, false, bytes(""));
    }

    function testBPTAddLiquidityIntermediateStepExactOut() public {
        uint256 maxUsdcIn = poolInitAmount / 100;

        // Two-step path: USDC -> BPT -> DAI
        // The BPT addition is intermediate, triggering the "not first step" logic
        IBatchRouter.SwapPathStep[] memory steps = new IBatchRouter.SwapPathStep[](2);
        steps[0] = IBatchRouter.SwapPathStep({
            pool: pool, // Regular swap: USDC -> DAI
            tokenOut: dai,
            isBuffer: false
        });
        steps[1] = IBatchRouter.SwapPathStep({
            pool: address(pool), // Add liquidity: DAI -> BPT (NOT LAST STEP)
            tokenOut: IERC20(address(pool)),
            isBuffer: false
        });

        IBatchRouter.SwapPathExactAmountOut[] memory paths = new IBatchRouter.SwapPathExactAmountOut[](1);
        paths[0] = IBatchRouter.SwapPathExactAmountOut({
            tokenIn: usdc,
            steps: steps,
            exactAmountOut: MIN_AMOUNT / 10, // Very small BPT amount
            maxAmountIn: maxUsdcIn
        });

        vm.prank(alice);
        batchRouter.swapExactOut(paths, MAX_UINT256, false, bytes(""));
    }

    function testBPTRemoveLiquidityWithFlashloan() public {
        // This test specifically targets the flashloan logic in BPT remove operations
        // when stepLocals.isLastStep == false.

        uint256 exactDaiOut = poolInitAmount / 2000; // Very small amount

        // Create a 2-step path where BPT removal is NOT the last step.
        // This forces the intermediate BPT removal logic that uses flashloan.
        IBatchRouter.SwapPathStep[] memory steps = new IBatchRouter.SwapPathStep[](2);
        steps[0] = IBatchRouter.SwapPathStep({
            pool: address(pool), // Remove liquidity: BPT -> DAI (NOT LAST STEP)
            tokenOut: dai,
            isBuffer: false
        });
        steps[1] = IBatchRouter.SwapPathStep({
            pool: pool, // Regular swap: DAI -> USDC
            tokenOut: usdc,
            isBuffer: false
        });

        IBatchRouter.SwapPathExactAmountOut[] memory paths = new IBatchRouter.SwapPathExactAmountOut[](1);
        paths[0] = IBatchRouter.SwapPathExactAmountOut({
            tokenIn: IERC20(address(pool)), // Start with BPT
            steps: steps,
            exactAmountOut: exactDaiOut,
            maxAmountIn: poolInitAmount / 10
        });

        // Give Alice some BPT.
        vm.startPrank(lp);
        IERC20(pool).transfer(alice, poolInitAmount / 10);
        vm.stopPrank();

        vm.prank(alice);
        batchRouter.swapExactOut(paths, MAX_UINT256, false, bytes(""));
    }

    function testBPTRefundUnusedFlashloan() public {
        // This targets the refund logic.
        // We need a scenario where bptAmountIn < stepMaxAmountIn.

        uint256 smallDaiOut = MIN_AMOUNT; // Very small amount to ensure unused flashloan

        // Multi-step with intermediate BPT remove that will have unused flashloan.
        IBatchRouter.SwapPathStep[] memory steps = new IBatchRouter.SwapPathStep[](2);
        steps[0] = IBatchRouter.SwapPathStep({
            pool: address(pool), // Remove liquidity with flashloan
            tokenOut: dai,
            isBuffer: false
        });
        steps[1] = IBatchRouter.SwapPathStep({
            pool: pool, // Regular swap
            tokenOut: usdc,
            isBuffer: false
        });

        IBatchRouter.SwapPathExactAmountOut[] memory paths = new IBatchRouter.SwapPathExactAmountOut[](1);
        paths[0] = IBatchRouter.SwapPathExactAmountOut({
            tokenIn: IERC20(address(pool)),
            steps: steps,
            exactAmountOut: smallDaiOut, // Very small output to ensure refund
            maxAmountIn: poolInitAmount // Large max to allow flashloan
        });

        // Give Alice some BPT.
        vm.startPrank(lp);
        IERC20(pool).transfer(alice, poolInitAmount);
        vm.stopPrank();

        vm.prank(alice);
        batchRouter.swapExactOut(paths, MAX_UINT256, false, bytes(""));
    }

    /***************************************************************************
                                Query Functions
    ***************************************************************************/

    function testQueryBPTOperations() public {
        uint256 bptAmountIn = poolInitAmount / 100;

        IBatchRouter.SwapPathStep[] memory steps = new IBatchRouter.SwapPathStep[](1);
        steps[0] = IBatchRouter.SwapPathStep({ pool: address(pool), tokenOut: dai, isBuffer: false });

        IBatchRouter.SwapPathExactAmountIn[] memory paths = new IBatchRouter.SwapPathExactAmountIn[](1);
        paths[0] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: IERC20(address(pool)),
            steps: steps,
            exactAmountIn: bptAmountIn,
            minAmountOut: 1
        });

        _prankStaticCall();
        (uint256[] memory pathAmountsOut, , ) = batchRouter.querySwapExactIn(paths, alice, bytes(""));

        assertGt(pathAmountsOut[0], 0, "Query should return positive amount");
    }
}
