// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { LiquidityManagement, PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IRouterCommon } from "@balancer-labs/v3-interfaces/contracts/vault/IRouterCommon.sol";
import { ISenderGuard } from "@balancer-labs/v3-interfaces/contracts/vault/ISenderGuard.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IAllowanceTransfer } from "permit2/src/interfaces/IAllowanceTransfer.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/BatchRouterTypes.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";

import { AggregatorBatchRouter } from "../../contracts/AggregatorBatchRouter.sol";
import { AggregatorBatchHooks } from "../../contracts/AggregatorBatchHooks.sol";
import { PoolFactoryMock, BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract AggregatorBatchRouterTest is BaseVaultTest {
    using ArrayHelpers for *;

    uint256 constant MIN_SWAP_AMOUNT = 1e6;

    // Track the indices for the standard dai/usdc pool.
    uint256 internal daiIdx;
    uint256 internal usdcIdx;

    // Additional pool for multi-hop tests.
    address internal secondPool;
    uint256 internal wethIdx;

    uint256 internal bufferAmount;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        // Create additional pool for multi-hop: USDC/WETH.
        secondPool = _createSecondPool();

        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));
        (usdcIdx, wethIdx) = getSortedIndexes(address(usdc), address(weth));
    }

    function _createSecondPool() internal returns (address newPool) {
        // Create USDC/WETH pool for multi-hop testing.
        newPool = address(deployPoolMock(IVault(address(vault)), "USDC/WETH Pool", "USDCWETH"));
        vm.label(newPool, "secondPool");

        LiquidityManagement memory liquidityManagement;
        PoolRoleAccounts memory roleAccounts;
        roleAccounts.poolCreator = lp;

        IERC20[] memory tokens = new IERC20[](2);
        tokens[0] = usdc;
        tokens[1] = weth;

        // Register the second pool.
        PoolFactoryMock(poolFactory).registerPool(
            newPool,
            vault.buildTokenConfig(tokens),
            roleAccounts,
            poolHooksContract,
            liquidityManagement
        );

        vm.startPrank(lp);
        _initPool(newPool, [poolInitAmount, poolInitAmount].toMemoryArray(), 0);
        vm.stopPrank();

        return newPool;
    }

    /***************************************************************************
                                 Single Step Swaps
    ***************************************************************************/

    function testSwapExactIn_SingleStep() public {
        uint256 exactAmountIn = MIN_SWAP_AMOUNT;

        // Create single step path.
        SwapPathStep[] memory steps = new SwapPathStep[](1);
        steps[0] = SwapPathStep({ pool: pool, tokenOut: dai, isBuffer: false });

        SwapPathExactAmountIn[] memory paths = new SwapPathExactAmountIn[](1);
        paths[0] = SwapPathExactAmountIn({
            tokenIn: usdc,
            steps: steps,
            exactAmountIn: exactAmountIn,
            minAmountOut: 0
        });

        // Transfer tokens to the Vault in advance (aggregator/pre-paid pattern).
        vm.startPrank(alice);
        usdc.transfer(address(vault), exactAmountIn);

        uint256[] memory poolBalancesBefore = vault.getCurrentLiveBalances(pool);
        uint256 aliceDaiBalanceBefore = dai.balanceOf(alice);
        uint256 aliceUsdcBalanceBefore = usdc.balanceOf(alice);

        (
            uint256[] memory pathAmountsOut,
            address[] memory tokensOut,
            uint256[] memory amountsOut
        ) = aggregatorBatchRouter.swapExactIn(paths, MAX_UINT256, false, bytes(""));
        vm.stopPrank();

        // Verify results.
        assertEq(pathAmountsOut.length, 1, "Should have one path result");
        assertEq(tokensOut.length, 1, "Should have one output token");
        assertEq(tokensOut[0], address(dai), "Output token should be DAI");
        assertEq(amountsOut[0], pathAmountsOut[0], "Amounts should match");

        // Verify balances.
        uint256[] memory poolBalancesAfter = vault.getCurrentLiveBalances(pool);
        assertEq(dai.balanceOf(alice), aliceDaiBalanceBefore + pathAmountsOut[0], "Wrong DAI balance");
        assertEq(usdc.balanceOf(alice), aliceUsdcBalanceBefore, "USDC balance should be unchanged after transfer");
        assertEq(poolBalancesAfter[daiIdx], poolBalancesBefore[daiIdx] - pathAmountsOut[0], "Wrong DAI pool balance");
        assertEq(poolBalancesAfter[usdcIdx], poolBalancesBefore[usdcIdx] + exactAmountIn, "Wrong USDC pool balance");
    }

    function testSwapExactOut_SingleStep() public {
        uint256 exactAmountOut = MIN_SWAP_AMOUNT;
        uint256 maxAmountIn = poolInitAmount;

        // Create single step path.
        SwapPathStep[] memory steps = new SwapPathStep[](1);
        steps[0] = SwapPathStep({ pool: pool, tokenOut: dai, isBuffer: false });

        SwapPathExactAmountOut[] memory paths = new SwapPathExactAmountOut[](1);
        paths[0] = SwapPathExactAmountOut({
            tokenIn: usdc,
            steps: steps,
            exactAmountOut: exactAmountOut,
            maxAmountIn: maxAmountIn
        });

        // Transfer tokens to the Vault in advance (aggregator/pre-paid pattern).
        vm.startPrank(alice);
        usdc.transfer(address(vault), maxAmountIn);

        uint256[] memory poolBalancesBefore = vault.getCurrentLiveBalances(pool);
        uint256 aliceDaiBalanceBefore = dai.balanceOf(alice);
        uint256 aliceUsdcBalanceBefore = usdc.balanceOf(alice);

        (uint256[] memory pathAmountsIn, address[] memory tokensIn, uint256[] memory amountsIn) = aggregatorBatchRouter
            .swapExactOut(paths, MAX_UINT256, false, bytes(""));
        vm.stopPrank();

        // Verify results.
        assertEq(pathAmountsIn.length, 1, "Should have one path result");
        assertEq(tokensIn.length, 1, "Should have one input token");
        assertEq(tokensIn[0], address(usdc), "Input token should be USDC");
        assertEq(amountsIn[0], pathAmountsIn[0], "Amounts should match");

        // Verify balances - Alice should receive exactAmountOut DAI and get back unused USDC.
        uint256[] memory poolBalancesAfter = vault.getCurrentLiveBalances(pool);
        assertEq(dai.balanceOf(alice), aliceDaiBalanceBefore + exactAmountOut, "Wrong DAI balance");
        assertEq(
            usdc.balanceOf(alice),
            aliceUsdcBalanceBefore + (maxAmountIn - pathAmountsIn[0]),
            "Wrong USDC balance"
        );
        assertLt(pathAmountsIn[0], maxAmountIn, "Should use less than max amount in");
        assertEq(poolBalancesAfter[daiIdx], poolBalancesBefore[daiIdx] - exactAmountOut, "Wrong DAI pool balance");
        assertEq(poolBalancesAfter[usdcIdx], poolBalancesBefore[usdcIdx] + pathAmountsIn[0], "Wrong USDC pool balance");
    }

    /***************************************************************************
                                 Multi-Step Swaps
    ***************************************************************************/

    function testSwapExactIn_MultiStep() public {
        uint256 exactAmountIn = MIN_SWAP_AMOUNT;

        // Create multi-step path: DAI -> USDC -> WETH.
        SwapPathStep[] memory steps = new SwapPathStep[](2);
        steps[0] = SwapPathStep({ pool: pool, tokenOut: usdc, isBuffer: false });
        steps[1] = SwapPathStep({ pool: secondPool, tokenOut: weth, isBuffer: false });

        SwapPathExactAmountIn[] memory paths = new SwapPathExactAmountIn[](1);
        paths[0] = SwapPathExactAmountIn({ tokenIn: dai, steps: steps, exactAmountIn: exactAmountIn, minAmountOut: 0 });

        // Transfer tokens to the Vault in advance (aggregator/pre-paid pattern).
        vm.startPrank(alice);
        dai.transfer(address(vault), exactAmountIn);

        uint256 aliceWethBalanceBefore = weth.balanceOf(alice);
        uint256 aliceDaiBalanceBefore = dai.balanceOf(alice);

        (uint256[] memory pathAmountsOut, address[] memory tokensOut, ) = aggregatorBatchRouter.swapExactIn(
            paths,
            MAX_UINT256,
            false,
            bytes("")
        );
        vm.stopPrank();

        // Verify results.
        assertEq(pathAmountsOut.length, 1, "Should have one path result");
        assertEq(tokensOut.length, 1, "Should have one output token");
        assertEq(tokensOut[0], address(weth), "Output token should be WETH");
        assertGt(pathAmountsOut[0], 0, "Should receive some WETH");

        // Verify balances - DAI already transferred, so balance should be unchanged.
        assertEq(weth.balanceOf(alice), aliceWethBalanceBefore + pathAmountsOut[0], "Wrong WETH balance");
        assertEq(dai.balanceOf(alice), aliceDaiBalanceBefore, "DAI balance should be unchanged after transfer");
    }

    function testSwapExactOut_MultiStep() public {
        uint256 exactAmountOut = MIN_SWAP_AMOUNT;
        uint256 maxAmountIn = poolInitAmount;

        // Create multi-step path: DAI -> USDC -> WETH.
        SwapPathStep[] memory steps = new SwapPathStep[](2);
        steps[0] = SwapPathStep({ pool: pool, tokenOut: usdc, isBuffer: false });
        steps[1] = SwapPathStep({ pool: secondPool, tokenOut: weth, isBuffer: false });

        SwapPathExactAmountOut[] memory paths = new SwapPathExactAmountOut[](1);
        paths[0] = SwapPathExactAmountOut({
            tokenIn: dai,
            steps: steps,
            exactAmountOut: exactAmountOut,
            maxAmountIn: maxAmountIn
        });

        // Transfer tokens to the Vault in advance (aggregator/pre-paid pattern).
        vm.startPrank(alice);
        dai.transfer(address(vault), maxAmountIn);

        uint256 aliceWethBalanceBefore = weth.balanceOf(alice);
        uint256 aliceDaiBalanceBefore = dai.balanceOf(alice);

        (uint256[] memory pathAmountsIn, address[] memory tokensIn, ) = aggregatorBatchRouter.swapExactOut(
            paths,
            MAX_UINT256,
            false,
            bytes("")
        );
        vm.stopPrank();

        // Verify results.
        assertEq(pathAmountsIn.length, 1, "Should have one path result");
        assertEq(tokensIn.length, 1, "Should have one input token");
        assertEq(tokensIn[0], address(dai), "Input token should be DAI");
        assertLt(pathAmountsIn[0], maxAmountIn, "Should use less than max amount in");

        // Verify balances - Alice should receive exactAmountOut WETH and get back unused DAI.
        assertEq(weth.balanceOf(alice), aliceWethBalanceBefore + exactAmountOut, "Wrong WETH balance");
        assertEq(dai.balanceOf(alice), aliceDaiBalanceBefore + (maxAmountIn - pathAmountsIn[0]), "Wrong DAI balance");
    }

    /***************************************************************************
                                 Multiple Paths
    ***************************************************************************/

    function testSwapExactIn_MultiplePaths() public {
        uint256 exactAmountIn1 = MIN_SWAP_AMOUNT;
        uint256 exactAmountIn2 = MIN_SWAP_AMOUNT * 2;

        // Path 1: DAI -> USDC.
        SwapPathStep[] memory steps1 = new SwapPathStep[](1);
        steps1[0] = SwapPathStep({ pool: pool, tokenOut: usdc, isBuffer: false });

        // Path 2: DAI -> USDC -> WETH.
        SwapPathStep[] memory steps2 = new SwapPathStep[](2);
        steps2[0] = SwapPathStep({ pool: pool, tokenOut: usdc, isBuffer: false });
        steps2[1] = SwapPathStep({ pool: secondPool, tokenOut: weth, isBuffer: false });

        SwapPathExactAmountIn[] memory paths = new SwapPathExactAmountIn[](2);
        paths[0] = SwapPathExactAmountIn({
            tokenIn: dai,
            steps: steps1,
            exactAmountIn: exactAmountIn1,
            minAmountOut: 0
        });
        paths[1] = SwapPathExactAmountIn({
            tokenIn: dai,
            steps: steps2,
            exactAmountIn: exactAmountIn2,
            minAmountOut: 0
        });

        // Transfer tokens to the Vault in advance (aggregator/pre-paid pattern).
        vm.startPrank(alice);
        dai.transfer(address(vault), exactAmountIn1 + exactAmountIn2);

        uint256 aliceUsdcBalanceBefore = usdc.balanceOf(alice);
        uint256 aliceWethBalanceBefore = weth.balanceOf(alice);
        uint256 aliceDaiBalanceBefore = dai.balanceOf(alice);

        (uint256[] memory pathAmountsOut, address[] memory tokensOut, ) = aggregatorBatchRouter.swapExactIn(
            paths,
            MAX_UINT256,
            false,
            bytes("")
        );
        vm.stopPrank();

        // Verify results.
        assertEq(pathAmountsOut.length, 2, "Should have two path results");
        assertEq(tokensOut.length, 2, "Should have two output tokens");

        // Should have both USDC and WETH as outputs.
        bool hasUsdc = false;
        bool hasWeth = false;
        for (uint256 i = 0; i < tokensOut.length; i++) {
            if (tokensOut[i] == address(usdc)) hasUsdc = true;
            if (tokensOut[i] == address(weth)) hasWeth = true;
        }
        assertTrue(hasUsdc, "Should have USDC output");
        assertTrue(hasWeth, "Should have WETH output");

        // Verify balances changed - DAI already transferred, so balance should be unchanged.
        assertGt(usdc.balanceOf(alice), aliceUsdcBalanceBefore, "Should receive USDC");
        assertGt(weth.balanceOf(alice), aliceWethBalanceBefore, "Should receive WETH");
        assertEq(dai.balanceOf(alice), aliceDaiBalanceBefore, "DAI balance should be unchanged after transfer");
    }

    /***************************************************************************
                                      Queries
    ***************************************************************************/

    function testQuerySwapExactIn() public {
        uint256 exactAmountIn = MIN_SWAP_AMOUNT;

        // Create single step path.
        SwapPathStep[] memory steps = new SwapPathStep[](1);
        steps[0] = SwapPathStep({ pool: pool, tokenOut: dai, isBuffer: false });

        SwapPathExactAmountIn[] memory paths = new SwapPathExactAmountIn[](1);
        paths[0] = SwapPathExactAmountIn({
            tokenIn: usdc,
            steps: steps,
            exactAmountIn: exactAmountIn,
            minAmountOut: 1 // This should be zeroed out by the query function
        });

        // Query without user balance changes.
        uint256 aliceDaiBalanceBefore = dai.balanceOf(alice);
        uint256 aliceUsdcBalanceBefore = usdc.balanceOf(alice);

        _prankStaticCall();
        (uint256[] memory pathAmountsOut, address[] memory tokensOut, ) = aggregatorBatchRouter.querySwapExactIn(
            paths,
            alice,
            bytes("")
        );

        // Verify user balances are unchanged (no actual token transfers in query).
        assertEq(dai.balanceOf(alice), aliceDaiBalanceBefore, "Alice DAI balance should be unchanged");
        assertEq(usdc.balanceOf(alice), aliceUsdcBalanceBefore, "Alice USDC balance should be unchanged");

        // Verify query results.
        assertEq(pathAmountsOut.length, 1, "Should have one path result");
        assertEq(tokensOut.length, 1, "Should have one output token");
        assertEq(tokensOut[0], address(dai), "Output token should be DAI");
        assertGt(pathAmountsOut[0], 0, "Should return positive amount out");
    }

    function testQuerySwapExactOut() public {
        uint256 exactAmountOut = MIN_SWAP_AMOUNT;

        // Create single step path.
        SwapPathStep[] memory steps = new SwapPathStep[](1);
        steps[0] = SwapPathStep({ pool: pool, tokenOut: dai, isBuffer: false });

        SwapPathExactAmountOut[] memory paths = new SwapPathExactAmountOut[](1);
        paths[0] = SwapPathExactAmountOut({
            tokenIn: usdc,
            steps: steps,
            exactAmountOut: exactAmountOut,
            maxAmountIn: 1 // This should be set to max by the query function
        });

        // Query without user balance changes.
        uint256 aliceDaiBalanceBefore = dai.balanceOf(alice);
        uint256 aliceUsdcBalanceBefore = usdc.balanceOf(alice);

        _prankStaticCall();
        (uint256[] memory pathAmountsIn, address[] memory tokensIn, ) = aggregatorBatchRouter.querySwapExactOut(
            paths,
            alice,
            bytes("")
        );

        // Verify user balances are unchanged (no actual token transfers in query).
        assertEq(dai.balanceOf(alice), aliceDaiBalanceBefore, "Alice DAI balance should be unchanged");
        assertEq(usdc.balanceOf(alice), aliceUsdcBalanceBefore, "Alice USDC balance should be unchanged");

        // Verify query results.
        assertEq(pathAmountsIn.length, 1, "Should have one path result");
        assertEq(tokensIn.length, 1, "Should have one input token");
        assertEq(tokensIn[0], address(usdc), "Input token should be USDC");
        assertGt(pathAmountsIn[0], 0, "Should return positive amount in");
    }

    /***************************************************************************
                                   Error Cases
    ***************************************************************************/

    function testSwapExactInDeadline() public {
        SwapPathStep[] memory steps = new SwapPathStep[](1);
        steps[0] = SwapPathStep({ pool: pool, tokenOut: dai, isBuffer: false });

        SwapPathExactAmountIn[] memory paths = new SwapPathExactAmountIn[](1);
        paths[0] = SwapPathExactAmountIn({
            tokenIn: usdc,
            steps: steps,
            exactAmountIn: MIN_SWAP_AMOUNT,
            minAmountOut: 0
        });

        vm.startPrank(alice);
        usdc.transfer(address(vault), MIN_SWAP_AMOUNT);

        vm.expectRevert(ISenderGuard.SwapDeadline.selector);
        aggregatorBatchRouter.swapExactIn(paths, block.timestamp - 1, false, bytes(""));
        vm.stopPrank();
    }

    function testSwapExactOutDeadline() public {
        SwapPathStep[] memory steps = new SwapPathStep[](1);
        steps[0] = SwapPathStep({ pool: pool, tokenOut: dai, isBuffer: false });

        SwapPathExactAmountOut[] memory paths = new SwapPathExactAmountOut[](1);
        paths[0] = SwapPathExactAmountOut({
            tokenIn: usdc,
            steps: steps,
            exactAmountOut: MIN_SWAP_AMOUNT,
            maxAmountIn: poolInitAmount
        });

        vm.startPrank(alice);
        usdc.transfer(address(vault), poolInitAmount);

        vm.expectRevert(ISenderGuard.SwapDeadline.selector);
        aggregatorBatchRouter.swapExactOut(paths, block.timestamp - 1, false, bytes(""));
        vm.stopPrank();
    }

    function testInsufficientFunds() public {
        uint256 exactAmountIn = MIN_SWAP_AMOUNT;

        SwapPathStep[] memory steps = new SwapPathStep[](1);
        steps[0] = SwapPathStep({ pool: pool, tokenOut: dai, isBuffer: false });

        SwapPathExactAmountIn[] memory paths = new SwapPathExactAmountIn[](1);
        paths[0] = SwapPathExactAmountIn({
            tokenIn: usdc,
            steps: steps,
            exactAmountIn: exactAmountIn,
            minAmountOut: 0
        });

        // Don't transfer enough tokens to the Vault.
        vm.startPrank(alice);
        usdc.transfer(address(vault), exactAmountIn / 2);

        vm.expectRevert(IVaultErrors.BalanceNotSettled.selector);
        aggregatorBatchRouter.swapExactIn(paths, MAX_UINT256, false, bytes(""));
        vm.stopPrank();
    }

    /***************************************************************************
                              Unsupported Operations
    ***************************************************************************/

    function testPermitBatchAndCallNotSupported() public {
        IRouterCommon.PermitApproval[] memory permitApprovals;
        bytes[] memory permitCalls;
        bytes[] memory multicallData;

        // Create empty PermitBatch struct.
        IAllowanceTransfer.PermitBatch memory permitBatch = IAllowanceTransfer.PermitBatch({
            details: new IAllowanceTransfer.PermitDetails[](0),
            spender: address(0),
            sigDeadline: 0
        });

        vm.expectRevert(IRouterCommon.OperationNotSupported.selector);
        aggregatorBatchRouter.permitBatchAndCall(permitApprovals, permitCalls, permitBatch, bytes(""), multicallData);
    }

    function testMulticallNotSupported() public {
        bytes[] memory calls;

        vm.expectRevert(IRouterCommon.OperationNotSupported.selector);
        aggregatorBatchRouter.multicall(calls);
    }

    function testOperationNotSupportedForBPTOperations() public {
        // Create a step where pool address equals tokenIn (which would be BPT).
        SwapPathStep[] memory steps = new SwapPathStep[](1);
        steps[0] = SwapPathStep({
            pool: address(usdc), // This makes pool == tokenIn, triggering BPT logic
            tokenOut: dai,
            isBuffer: false
        });

        SwapPathExactAmountIn[] memory paths = new SwapPathExactAmountIn[](1);
        paths[0] = SwapPathExactAmountIn({
            tokenIn: usdc,
            steps: steps,
            exactAmountIn: MIN_SWAP_AMOUNT,
            minAmountOut: 0
        });

        vm.startPrank(alice);
        usdc.transfer(address(vault), MIN_SWAP_AMOUNT);

        vm.expectRevert(IRouterCommon.OperationNotSupported.selector);
        aggregatorBatchRouter.swapExactIn(paths, MAX_UINT256, false, bytes(""));
        vm.stopPrank();
    }

    /***************************************************************************
                                 Router Info
    ***************************************************************************/

    function testRouterVersion() public view {
        assertEq(aggregatorBatchRouter.version(), AGGREGATOR_BATCH_ROUTER_VERSION, "Router version mismatch");
    }

    function testRouterVault() public view {
        assertEq(address(aggregatorBatchRouter.getVault()), address(vault), "Router vault mismatch");
    }

    /***************************************************************************
                              Fuzz Testing
    ***************************************************************************/

    function testSwapExactIn__Fuzz(uint256 swapAmount) public {
        uint256[] memory poolBalances = vault.getCurrentLiveBalances(pool);
        swapAmount = bound(swapAmount, MIN_SWAP_AMOUNT, poolBalances[daiIdx] / 2);

        SwapPathStep[] memory steps = new SwapPathStep[](1);
        steps[0] = SwapPathStep({ pool: pool, tokenOut: dai, isBuffer: false });

        SwapPathExactAmountIn[] memory paths = new SwapPathExactAmountIn[](1);
        paths[0] = SwapPathExactAmountIn({ tokenIn: usdc, steps: steps, exactAmountIn: swapAmount, minAmountOut: 0 });

        vm.startPrank(alice);
        usdc.transfer(address(vault), swapAmount);

        uint256 aliceDaiBalanceBefore = dai.balanceOf(alice);
        uint256 aliceUsdcBalanceBefore = usdc.balanceOf(alice);

        (uint256[] memory pathAmountsOut, , ) = aggregatorBatchRouter.swapExactIn(paths, MAX_UINT256, false, bytes(""));
        vm.stopPrank();

        // Verify balances - USDC already transferred, so balance should be unchanged.
        assertEq(dai.balanceOf(alice), aliceDaiBalanceBefore + pathAmountsOut[0], "Wrong DAI balance");
        assertEq(usdc.balanceOf(alice), aliceUsdcBalanceBefore, "USDC balance should be unchanged after transfer");
        assertGt(pathAmountsOut[0], 0, "Should receive positive amount out");
    }

    function testQueryVsActualSwap__Fuzz(uint256 swapAmount) public {
        uint256[] memory poolBalances = vault.getCurrentLiveBalances(pool);
        swapAmount = bound(swapAmount, MIN_SWAP_AMOUNT, poolBalances[daiIdx] / 2);

        SwapPathStep[] memory steps = new SwapPathStep[](1);
        steps[0] = SwapPathStep({ pool: pool, tokenOut: dai, isBuffer: false });

        SwapPathExactAmountIn[] memory paths = new SwapPathExactAmountIn[](1);
        paths[0] = SwapPathExactAmountIn({ tokenIn: usdc, steps: steps, exactAmountIn: swapAmount, minAmountOut: 0 });

        uint256 snapshot = vm.snapshotState();

        // First query the swap.
        _prankStaticCall();
        (uint256[] memory queryAmountsOut, , ) = aggregatorBatchRouter.querySwapExactIn(paths, alice, bytes(""));
        vm.revertToState(snapshot);

        // Then execute the actual swap.
        vm.startPrank(alice);
        usdc.transfer(address(vault), swapAmount);
        (uint256[] memory actualAmountsOut, , ) = aggregatorBatchRouter.swapExactIn(
            paths,
            MAX_UINT256,
            false,
            bytes("")
        );
        vm.stopPrank();

        // Query and actual should match.
        assertEq(queryAmountsOut.length, actualAmountsOut.length, "Query and actual amounts differ in length");
        assertEq(queryAmountsOut[0], actualAmountsOut[0], "Query amount differs from actual swap amount");
    }

    /***************************************************************************
                              Buffers / Edge Cases
    ***************************************************************************/

    function testBufferOperationNotSupported() public {
        uint256 exactAmountIn = MIN_SWAP_AMOUNT;

        // Create buffer operation step.
        SwapPathStep[] memory steps = new SwapPathStep[](1);
        steps[0] = SwapPathStep({
            pool: address(dai), // Any address for buffer operation
            tokenOut: usdc,
            isBuffer: true // Trigger buffer operations
        });

        SwapPathExactAmountIn[] memory paths = new SwapPathExactAmountIn[](1);
        paths[0] = SwapPathExactAmountIn({ tokenIn: dai, steps: steps, exactAmountIn: exactAmountIn, minAmountOut: 0 });

        // Transfer tokens to the Vault in advance (aggregator/pre-paid pattern).
        vm.startPrank(alice);
        dai.transfer(address(vault), exactAmountIn);

        // This should revert because the AggregatorBatchRouter doesn't properly handle buffer operations
        // when there's no buffer initialized for this token.
        vm.expectRevert(); // Any revert is fine, we just want to hit the buffer code path
        aggregatorBatchRouter.swapExactIn(paths, MAX_UINT256, false, bytes(""));
        vm.stopPrank();
    }

    function testBufferOperationExactOut() public {
        uint256 exactAmountOut = MIN_SWAP_AMOUNT;
        uint256 maxAmountIn = MIN_SWAP_AMOUNT * 2;

        // Create buffer operation step.
        SwapPathStep[] memory steps = new SwapPathStep[](1);
        steps[0] = SwapPathStep({ pool: address(dai), tokenOut: usdc, isBuffer: true });

        SwapPathExactAmountOut[] memory paths = new SwapPathExactAmountOut[](1);
        paths[0] = SwapPathExactAmountOut({
            tokenIn: dai,
            steps: steps,
            exactAmountOut: exactAmountOut,
            maxAmountIn: maxAmountIn
        });

        // Transfer tokens to the Vault in advance (aggregator/pre-paid pattern).
        vm.startPrank(alice);
        dai.transfer(address(vault), maxAmountIn);

        // This should revert because buffer is not properly set up.
        vm.expectRevert();
        aggregatorBatchRouter.swapExactOut(paths, MAX_UINT256, false, bytes(""));
        vm.stopPrank();
    }

    function testInsufficientFundsExactOut() public {
        uint256 exactAmountOut = MIN_SWAP_AMOUNT;
        uint256 maxAmountIn = MIN_SWAP_AMOUNT * 2;

        SwapPathStep[] memory steps = new SwapPathStep[](1);
        steps[0] = SwapPathStep({ pool: pool, tokenOut: dai, isBuffer: false });

        SwapPathExactAmountOut[] memory paths = new SwapPathExactAmountOut[](1);
        paths[0] = SwapPathExactAmountOut({
            tokenIn: usdc,
            steps: steps,
            exactAmountOut: exactAmountOut,
            maxAmountIn: maxAmountIn
        });

        // Transfer insufficient tokens to vault (less than maxAmountIn).
        vm.startPrank(alice);
        usdc.transfer(address(vault), maxAmountIn / 2);

        vm.expectRevert(IVaultErrors.BalanceNotSettled.selector);
        aggregatorBatchRouter.swapExactOut(paths, MAX_UINT256, false, bytes(""));
        vm.stopPrank();
    }

    function testBPTOperationNotSupportedExactOut() public {
        uint256 exactAmountOut = MIN_SWAP_AMOUNT;
        uint256 maxAmountIn = MIN_SWAP_AMOUNT * 2;

        // Create a step where pool address equals tokenOut (BPT operation - add liquidity).
        SwapPathStep[] memory steps = new SwapPathStep[](1);
        steps[0] = SwapPathStep({
            pool: address(dai), // pool == tokenOut triggers BPT add liquidity logic
            tokenOut: dai, // This makes it a BPT operation
            isBuffer: false
        });

        SwapPathExactAmountOut[] memory paths = new SwapPathExactAmountOut[](1);
        paths[0] = SwapPathExactAmountOut({
            tokenIn: usdc,
            steps: steps,
            exactAmountOut: exactAmountOut,
            maxAmountIn: maxAmountIn
        });

        vm.startPrank(alice);
        usdc.transfer(address(vault), maxAmountIn);

        vm.expectRevert(IRouterCommon.OperationNotSupported.selector);
        aggregatorBatchRouter.swapExactOut(paths, MAX_UINT256, false, bytes(""));
        vm.stopPrank();
    }
}
