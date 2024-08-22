// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { SwapKind } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IVaultEvents } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultEvents.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { IBatchRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IBatchRouter.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";

import { ERC4626TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC4626TestToken.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { BaseERC4626BufferTest } from "./utils/BaseERC4626BufferTest.sol";

contract YieldBearingPoolBufferAsVaultPrimitiveTest is BaseERC4626BufferTest {
    using ArrayHelpers for *;
    using FixedPoint for uint256;

    // The yield-bearing pool will have 100x the liquidity of the buffer.
    uint256 internal tooLargeSwapAmount = erc4626PoolInitialAmount / 2;
    // We will swap with 10% of the buffer.
    uint256 internal swapAmount;
    // LP can unbalance buffer with this amount.
    uint256 internal unbalancedUnderlyingDelta;

    uint256 internal bufferTestAmount;
    uint256 internal constant MAX_ERROR = 10;

    function setUp() public virtual override {
        bufferInitialAmount = erc4626PoolInitialAmount / 50;
        swapAmount = bufferInitialAmount / 10;
        unbalancedUnderlyingDelta = bufferInitialAmount / 2;
        bufferTestAmount = erc4626PoolInitialAmount / 100;
        BaseERC4626BufferTest.setUp();
    }

    function testAddLiquidityEvents() public {
        vm.startPrank(lp);
        // Can add the same amount again, since twice as much was minted.
        vm.expectEmit();
        emit IVaultEvents.LiquidityAddedToBuffer(waDAI, bufferInitialAmount, bufferInitialAmount);
        router.addLiquidityToBuffer(waDAI, bufferInitialAmount, bufferInitialAmount);

        vm.expectEmit();
        emit IVaultEvents.LiquidityAddedToBuffer(waUSDC, bufferInitialAmount, bufferInitialAmount);
        router.addLiquidityToBuffer(waUSDC, bufferInitialAmount, bufferInitialAmount);
        vm.stopPrank();
    }

    function testRemoveLiquidityEvents() public {
        // Authorizes router to call removeLiquidityFromBuffer (trusted router).
        authorizer.grantRole(vault.getActionId(IVaultAdmin.removeLiquidityFromBuffer.selector), address(router));

        (uint256 underlyingBalance, uint256 wrappedBalance) = vault.getBufferBalance(waDAI);
        uint256 bufferTotalShares = vault.getBufferTotalShares(waDAI);

        vm.expectEmit();
        emit IVaultEvents.LiquidityRemovedFromBuffer(
            waDAI,
            (underlyingBalance * bufferTestAmount) / bufferTotalShares,
            (wrappedBalance * bufferTestAmount) / bufferTotalShares
        );
        vm.prank(lp);
        vault.removeLiquidityFromBuffer(waDAI, bufferTestAmount);

        (underlyingBalance, wrappedBalance) = vault.getBufferBalance(waUSDC);
        bufferTotalShares = vault.getBufferTotalShares(waUSDC);

        vm.expectEmit();
        emit IVaultEvents.LiquidityRemovedFromBuffer(
            waUSDC,
            (underlyingBalance * bufferTestAmount) / bufferTotalShares,
            (wrappedBalance * bufferTestAmount) / bufferTotalShares
        );
        vm.prank(lp);
        vault.removeLiquidityFromBuffer(waUSDC, bufferTestAmount);
    }

    function testYieldBearingPoolSwapWithinBufferRangeExactIn() public {
        SwapResultLocals memory vars = _createSwapResultLocals(SwapKind.EXACT_IN);

        IBatchRouter.SwapPathExactAmountIn[] memory paths = _buildExactInPaths(swapAmount);

        vm.prank(alice);
        (uint256[] memory pathAmountsOut, address[] memory tokensOut, uint256[] memory amountsOut) = batchRouter
            .swapExactIn(paths, MAX_UINT256, false, bytes(""));

        // When the buffer has enough liquidity to wrap/unwrap, buffer balances should change by swapAmount
        // DAI buffer receives DAI from user.
        vars.expectedBufferBalanceAfterSwapDai = vars.bufferBalanceBeforeSwapDai + swapAmount;
        vars.expectedBufferBalanceAfterSwapWaDai =
            vars.bufferBalanceBeforeSwapWaDai -
            waDAI.convertToShares(swapAmount);
        // Yield-bearing pool receives WaDai from DAI buffer, and gives waUSDC to USDC buffer.
        vars.expectedBufferBalanceAfterSwapWaUsdc =
            vars.bufferBalanceBeforeSwapWaUsdc +
            waUSDC.convertToShares(swapAmount);
        // USDC buffer gives USDC to user.
        vars.expectedBufferBalanceAfterSwapUsdc = vars.bufferBalanceBeforeSwapUsdc - swapAmount;
        vars.expectedAliceDelta = swapAmount;

        _verifySwapResult(pathAmountsOut, tokensOut, amountsOut, vars);
    }

    function testYieldBearingPoolSwapWithinBufferRangeExactOut() public {
        SwapResultLocals memory vars = _createSwapResultLocals(SwapKind.EXACT_OUT);

        IBatchRouter.SwapPathExactAmountOut[] memory paths = _buildExactOutPaths(swapAmount);

        vm.prank(alice);
        (uint256[] memory pathAmountsIn, address[] memory tokensIn, uint256[] memory amountsIn) = batchRouter
            .swapExactOut(paths, MAX_UINT256, false, bytes(""));

        // When the buffer has enough liquidity to wrap/unwrap, buffer balances should change by swapAmount
        // DAI buffer receives DAI from user.
        vars.expectedBufferBalanceAfterSwapDai = vars.bufferBalanceBeforeSwapDai + swapAmount;
        vars.expectedBufferBalanceAfterSwapWaDai =
            vars.bufferBalanceBeforeSwapWaDai -
            waDAI.convertToShares(swapAmount);
        // Yield-bearing pool receives WaDai from DAI buffer, and gives waUSDC to USDC buffer.
        vars.expectedBufferBalanceAfterSwapWaUsdc =
            vars.bufferBalanceBeforeSwapWaUsdc +
            waUSDC.convertToShares(swapAmount);
        // USDC buffer gives USDC to user.
        vars.expectedBufferBalanceAfterSwapUsdc = vars.bufferBalanceBeforeSwapUsdc - swapAmount;
        // TODO review error tolerance (rounding issue with rates)
        vars.expectedAliceDelta = swapAmount;

        _verifySwapResult(pathAmountsIn, tokensIn, amountsIn, vars);
    }

    function testYieldBearingPoolSwapOutOfBufferRangeExactIn() public {
        SwapResultLocals memory vars = _createSwapResultLocals(SwapKind.EXACT_IN);

        IBatchRouter.SwapPathExactAmountIn[] memory paths = _buildExactInPaths(tooLargeSwapAmount);

        vm.prank(alice);
        (uint256[] memory pathAmountsOut, address[] memory tokensOut, uint256[] memory amountsOut) = batchRouter
            .swapExactIn(paths, MAX_UINT256, false, bytes(""));

        // When the buffer has not enough liquidity to wrap/unwrap and buffers were balanced, buffer balances should
        // not change
        vars.expectedBufferBalanceAfterSwapDai = vars.bufferBalanceBeforeSwapDai;
        vars.expectedBufferBalanceAfterSwapWaDai = vars.bufferBalanceBeforeSwapWaDai;
        vars.expectedBufferBalanceAfterSwapUsdc = vars.bufferBalanceBeforeSwapUsdc;
        vars.expectedBufferBalanceAfterSwapWaUsdc = vars.bufferBalanceBeforeSwapWaUsdc;
        vars.expectedAliceDelta = tooLargeSwapAmount;

        _verifySwapResult(pathAmountsOut, tokensOut, amountsOut, vars);
    }

    function testYieldBearingPoolSwapOutOfBufferRangeExactOut() public {
        SwapResultLocals memory vars = _createSwapResultLocals(SwapKind.EXACT_OUT);

        IBatchRouter.SwapPathExactAmountOut[] memory paths = _buildExactOutPaths(tooLargeSwapAmount);

        vm.prank(alice);
        (uint256[] memory pathAmountsIn, address[] memory tokensIn, uint256[] memory amountsIn) = batchRouter
            .swapExactOut(paths, MAX_UINT256, false, bytes(""));

        // When the buffer has not enough liquidity to wrap/unwrap and buffers were balanced, buffer balances should
        // not change.
        vars.expectedBufferBalanceAfterSwapDai = vars.bufferBalanceBeforeSwapDai;
        vars.expectedBufferBalanceAfterSwapWaDai = vars.bufferBalanceBeforeSwapWaDai;
        vars.expectedBufferBalanceAfterSwapUsdc = vars.bufferBalanceBeforeSwapUsdc;
        vars.expectedBufferBalanceAfterSwapWaUsdc = vars.bufferBalanceBeforeSwapWaUsdc;
        vars.expectedAliceDelta = tooLargeSwapAmount;

        _verifySwapResult(pathAmountsIn, tokensIn, amountsIn, vars);
    }

    function testYieldBearingPoolSwapUnbalancedBufferExactIn() public {
        vm.startPrank(lp);
        // Surplus of underlying.
        router.addLiquidityToBuffer(waDAI, unbalancedUnderlyingDelta, 0);
        // Surplus of wrapped.
        router.addLiquidityToBuffer(waUSDC, 0, waUSDC.convertToShares(unbalancedUnderlyingDelta));
        vm.stopPrank();

        SwapResultLocals memory vars = _createSwapResultLocals(SwapKind.EXACT_IN);

        IBatchRouter.SwapPathExactAmountIn[] memory paths = _buildExactInPaths(tooLargeSwapAmount);

        vm.prank(alice);
        (uint256[] memory pathAmountsOut, address[] memory tokensOut, uint256[] memory amountsOut) = batchRouter
            .swapExactIn(paths, MAX_UINT256, false, bytes(""));

        // When the buffer has not enough liquidity to wrap/unwrap and buffers were not balanced, buffers should be
        // perfectly balanced at the end, but only if the wrap/unwrap direction is the same as the operation executed
        // by the user. E.g.:
        // - If user is wrapping and buffer has a surplus of underlying, buffer will be balanced
        // - If user is unwrapping and buffer has a surplus of wrapped, buffer will be balanced
        // - But if user is wrapping and buffer has a surplus of wrapped, buffer will stay as is
        vars.expectedBufferBalanceAfterSwapDai = vars.bufferBalanceBeforeSwapDai - (unbalancedUnderlyingDelta / 2);
        vars.expectedBufferBalanceAfterSwapWaDai =
            vars.bufferBalanceBeforeSwapWaDai +
            waDAI.convertToShares(unbalancedUnderlyingDelta / 2);
        vars.expectedBufferBalanceAfterSwapUsdc = vars.bufferBalanceBeforeSwapUsdc + (unbalancedUnderlyingDelta / 2);
        vars.expectedBufferBalanceAfterSwapWaUsdc =
            vars.bufferBalanceBeforeSwapWaUsdc -
            waUSDC.convertToShares(unbalancedUnderlyingDelta / 2);
        vars.expectedAliceDelta = tooLargeSwapAmount;

        _verifySwapResult(pathAmountsOut, tokensOut, amountsOut, vars);
    }

    function testYieldBearingPoolSwapUnbalancedBufferExactOut() public {
        vm.startPrank(lp);
        // Surplus of underlying.
        router.addLiquidityToBuffer(waDAI, unbalancedUnderlyingDelta, 0);
        // Surplus of wrapped.
        router.addLiquidityToBuffer(waUSDC, 0, waUSDC.convertToShares(unbalancedUnderlyingDelta));
        vm.stopPrank();

        SwapResultLocals memory vars = _createSwapResultLocals(SwapKind.EXACT_OUT);

        IBatchRouter.SwapPathExactAmountOut[] memory paths = _buildExactOutPaths(tooLargeSwapAmount);

        vm.prank(alice);
        (uint256[] memory pathAmountsIn, address[] memory tokensIn, uint256[] memory amountsIn) = batchRouter
            .swapExactOut(paths, MAX_UINT256, false, bytes(""));

        // When the buffer has not enough liquidity to wrap/unwrap and buffers were not balanced, buffers should be
        // perfectly balanced at the end, but only if the wrap/unwrap direction is the same as the operation executed
        // by the user. E.g.:
        // - If user is wrapping and buffer has a surplus of underlying, buffer will be balanced
        // - If user is unwrapping and buffer has a surplus of wrapped, buffer will be balanced
        // - But if user is wrapping and buffer has a surplus of wrapped, buffer will stay as is
        vars.expectedBufferBalanceAfterSwapDai = vars.bufferBalanceBeforeSwapDai - (unbalancedUnderlyingDelta / 2);
        vars.expectedBufferBalanceAfterSwapWaDai =
            vars.bufferBalanceBeforeSwapWaDai +
            waDAI.convertToShares(unbalancedUnderlyingDelta / 2);
        vars.expectedBufferBalanceAfterSwapUsdc = vars.bufferBalanceBeforeSwapUsdc + (unbalancedUnderlyingDelta / 2);
        vars.expectedBufferBalanceAfterSwapWaUsdc =
            vars.bufferBalanceBeforeSwapWaUsdc -
            waUSDC.convertToShares(unbalancedUnderlyingDelta / 2);
        vars.expectedAliceDelta = tooLargeSwapAmount;

        _verifySwapResult(pathAmountsIn, tokensIn, amountsIn, vars);
    }

    function _buildExactInPaths(
        uint256 amount
    ) private view returns (IBatchRouter.SwapPathExactAmountIn[] memory paths) {
        IBatchRouter.SwapPathStep[] memory steps = new IBatchRouter.SwapPathStep[](3);
        paths = new IBatchRouter.SwapPathExactAmountIn[](1);

        // Since this is exact in, swaps will be executed in the order given.
        // Pre-swap through DAI buffer to get waDAI, then main swap waDAI for waUSDC in the yield-bearing pool,
        // and finally post-swap the waUSDC through the USDC buffer to calculate the USDC amount out.
        // The only token transfers are DAI in (given) and USDC out (calculated).
        steps[0] = IBatchRouter.SwapPathStep({ pool: address(waDAI), tokenOut: waDAI, isBuffer: true });
        steps[1] = IBatchRouter.SwapPathStep({ pool: erc4626Pool, tokenOut: waUSDC, isBuffer: false });
        steps[2] = IBatchRouter.SwapPathStep({ pool: address(waUSDC), tokenOut: usdc, isBuffer: true });

        paths[0] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: dai,
            steps: steps,
            exactAmountIn: amount,
            minAmountOut: amount - MAX_ERROR // Remove a max of 10 wei to compensate for rounding issues and rebalance
        });
    }

    function _buildExactOutPaths(
        uint256 amount
    ) private view returns (IBatchRouter.SwapPathExactAmountOut[] memory paths) {
        IBatchRouter.SwapPathStep[] memory steps = new IBatchRouter.SwapPathStep[](3);
        paths = new IBatchRouter.SwapPathExactAmountOut[](1);

        // Since this is exact out, swaps will be executed in reverse order (though we submit in logical order).
        // Pre-swap through the USDC buffer to get waUSDC, then main swap waUSDC for waDAI in the yield-bearing pool,
        // and finally post-swap the waDAI for DAI through the DAI buffer to calculate the DAI amount in.
        // The only token transfers are DAI in (calculated) and USDC out (given).
        steps[0] = IBatchRouter.SwapPathStep({ pool: address(waDAI), tokenOut: waDAI, isBuffer: true });
        steps[1] = IBatchRouter.SwapPathStep({ pool: erc4626Pool, tokenOut: waUSDC, isBuffer: false });
        steps[2] = IBatchRouter.SwapPathStep({ pool: address(waUSDC), tokenOut: usdc, isBuffer: true });

        paths[0] = IBatchRouter.SwapPathExactAmountOut({
            tokenIn: dai,
            steps: steps,
            maxAmountIn: amount + MAX_ERROR, // Add a max of 10 wei to compensate for rounding issues and rebalance
            exactAmountOut: amount
        });
    }

    struct SwapResultLocals {
        SwapKind kind;
        uint256 aliceBalanceBeforeSwapDai;
        uint256 aliceBalanceBeforeSwapUsdc;
        uint256 bufferBalanceBeforeSwapDai;
        uint256 bufferBalanceBeforeSwapWaDai;
        uint256 bufferBalanceBeforeSwapUsdc;
        uint256 bufferBalanceBeforeSwapWaUsdc;
        uint256 yieldBearingPoolBalanceBeforeSwapWaDai;
        uint256 yieldBearingPoolBalanceBeforeSwapWaUsdc;
        uint256 expectedAliceDelta;
        uint256 expectedBufferBalanceAfterSwapDai;
        uint256 expectedBufferBalanceAfterSwapWaDai;
        uint256 expectedBufferBalanceAfterSwapUsdc;
        uint256 expectedBufferBalanceAfterSwapWaUsdc;
    }

    function _createSwapResultLocals(SwapKind kind) private view returns (SwapResultLocals memory vars) {
        vars.kind = kind;
        vars.aliceBalanceBeforeSwapDai = dai.balanceOf(alice);
        vars.aliceBalanceBeforeSwapUsdc = usdc.balanceOf(alice);

        uint256 underlyingBalance;
        uint256 wrappedBalance;
        (underlyingBalance, wrappedBalance) = vault.getBufferBalance(IERC4626(waDAI));
        vars.bufferBalanceBeforeSwapDai = underlyingBalance;
        vars.bufferBalanceBeforeSwapWaDai = wrappedBalance;
        (underlyingBalance, wrappedBalance) = vault.getBufferBalance(IERC4626(waUSDC));
        vars.bufferBalanceBeforeSwapUsdc = underlyingBalance;
        vars.bufferBalanceBeforeSwapWaUsdc = wrappedBalance;

        uint256[] memory balancesRaw;
        (uint256 daiIdx, uint256 usdcIdx) = getSortedIndexes(address(waDAI), address(waUSDC));
        (, , balancesRaw, ) = vault.getPoolTokenInfo(erc4626Pool);
        vars.yieldBearingPoolBalanceBeforeSwapWaDai = balancesRaw[daiIdx];
        vars.yieldBearingPoolBalanceBeforeSwapWaUsdc = balancesRaw[usdcIdx];
    }

    function _verifySwapResult(
        uint256[] memory paths,
        address[] memory tokens,
        uint256[] memory amounts,
        SwapResultLocals memory vars
    ) private view {
        assertEq(paths.length, 1, "Incorrect output array length");

        assertEq(paths.length, tokens.length, "Output array length mismatch");
        assertEq(tokens.length, amounts.length, "Output array length mismatch");

        // Check results
        if (vars.kind == SwapKind.EXACT_IN) {
            // Rounding issues occurs in favor of vault, and are very small
            assertLe(paths[0], vars.expectedAliceDelta, "paths AmountOut must be <= expected amountOut");
            assertApproxEqAbs(paths[0], vars.expectedAliceDelta, MAX_ERROR, "Wrong path count");
            assertLe(paths[0], vars.expectedAliceDelta, "amounts AmountOut must be <= expected amountOut");
            assertApproxEqAbs(amounts[0], vars.expectedAliceDelta, MAX_ERROR, "Wrong amounts count");
            assertEq(tokens[0], address(usdc), "Wrong token for SwapKind");
        } else {
            // Rounding issues occurs in favor of vault, and are very small
            // TODO remove tolerance of 1 wei, when rounding issues with rates are solved
            assertGe(paths[0], vars.expectedAliceDelta - 1, "paths AmountIn must be >= expected amountIn");
            assertApproxEqAbs(paths[0], vars.expectedAliceDelta, MAX_ERROR, "Wrong path count");
            // TODO remove tolerance of 1 wei, when rounding issues with rates are solved
            assertGe(amounts[0], vars.expectedAliceDelta - 1, "amounts AmountIn must be >= expected amountIn");
            assertApproxEqAbs(amounts[0], vars.expectedAliceDelta, MAX_ERROR, "Wrong amounts count");
            assertEq(tokens[0], address(dai), "Wrong token for SwapKind");
        }

        // Tokens were transferred
        // TODO remove tolerance of 1 wei, when rounding issues with rates are solved
        assertLe(
            dai.balanceOf(alice),
            vars.aliceBalanceBeforeSwapDai - vars.expectedAliceDelta + 1,
            "Alice balance DAI must be <= expected balance"
        );
        assertApproxEqAbs(
            dai.balanceOf(alice),
            vars.aliceBalanceBeforeSwapDai - vars.expectedAliceDelta,
            MAX_ERROR,
            "Wrong ending balance of DAI for Alice"
        );
        // TODO remove tolerance of 1 wei, when rounding issues with rates are solved
        assertLe(
            usdc.balanceOf(alice),
            vars.aliceBalanceBeforeSwapUsdc + vars.expectedAliceDelta + 1,
            "Alice balance USDC must be <= expected balance"
        );
        assertApproxEqAbs(
            usdc.balanceOf(alice),
            vars.aliceBalanceBeforeSwapUsdc + vars.expectedAliceDelta,
            MAX_ERROR,
            "Wrong ending balance of USDC for Alice"
        );

        uint256[] memory balancesRaw;

        (uint256 daiIdx, uint256 usdcIdx) = getSortedIndexes(address(waDAI), address(waUSDC));
        (, , balancesRaw, ) = vault.getPoolTokenInfo(erc4626Pool);
        assertApproxEqAbs(
            balancesRaw[daiIdx],
            vars.yieldBearingPoolBalanceBeforeSwapWaDai + waDAI.convertToShares(vars.expectedAliceDelta),
            MAX_ERROR,
            "Wrong yield-bearing pool DAI balance"
        );
        assertApproxEqAbs(
            balancesRaw[usdcIdx],
            vars.yieldBearingPoolBalanceBeforeSwapWaUsdc - waUSDC.convertToShares(vars.expectedAliceDelta),
            MAX_ERROR,
            "Wrong yield-bearing pool USDC balance"
        );

        uint256 underlyingBalance;
        uint256 wrappedBalance;
        (underlyingBalance, wrappedBalance) = vault.getBufferBalance(IERC4626(waDAI));
        assertApproxEqAbs(
            underlyingBalance,
            vars.expectedBufferBalanceAfterSwapDai,
            MAX_ERROR,
            "Wrong DAI buffer pool underlying balance"
        );
        assertApproxEqAbs(
            wrappedBalance,
            vars.expectedBufferBalanceAfterSwapWaDai,
            MAX_ERROR,
            "Wrong DAI buffer pool wrapped balance"
        );

        (underlyingBalance, wrappedBalance) = vault.getBufferBalance(IERC4626(waUSDC));
        assertApproxEqAbs(
            underlyingBalance,
            vars.expectedBufferBalanceAfterSwapUsdc,
            MAX_ERROR,
            "Wrong USDC buffer pool underlying balance"
        );
        assertApproxEqAbs(
            wrappedBalance,
            vars.expectedBufferBalanceAfterSwapWaUsdc,
            MAX_ERROR,
            "Wrong USDC buffer pool wrapped balance"
        );
    }
}
