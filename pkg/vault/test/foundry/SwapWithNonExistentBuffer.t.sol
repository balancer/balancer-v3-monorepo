// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { TokenConfig, TokenType, SwapKind } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IBatchRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IBatchRouter.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";

import { ERC4626TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC4626TestToken.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";

import { PoolMock } from "../../contracts/test/PoolMock.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract SwapWithNonExistentBufferTest is BaseVaultTest {
    using ArrayHelpers for *;

    ERC4626TestToken internal waDAI;
    ERC4626TestToken internal waUSDC;

    // For two-token pools with waDAI/waUSDC, keep track of sorted token order.
    uint256 internal waDaiIdx;
    uint256 internal waUsdcIdx;

    address internal yieldBearingPool;

    // The yield-bearing pool will have 100x the liquidity of the buffer
    uint256 internal yieldBearingPoolAmount = 10e6 * 1e18;
    uint256 internal bufferAmount = 0;
    // We will swap with 10% of the yield-bearing pool.
    uint256 internal swapAmount = yieldBearingPoolAmount / 10;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        waDAI = new ERC4626TestToken(dai, "Wrapped aDAI", "waDAI", 18);
        vm.label(address(waDAI), "waDAI");

        // "USDC" is deliberately 18 decimals to test one thing at a time.
        waUSDC = new ERC4626TestToken(usdc, "Wrapped aUSDC", "waUSDC", 18);
        vm.label(address(waUSDC), "waUSDC");

        (waDaiIdx, waUsdcIdx) = getSortedIndexes(address(waDAI), address(waUSDC));

        initializeYieldBearingPool();
    }

    function initializeYieldBearingPool() private {
        TokenConfig[] memory tokenConfig = new TokenConfig[](2);
        tokenConfig[waDaiIdx].token = IERC20(waDAI);
        tokenConfig[waUsdcIdx].token = IERC20(waUSDC);
        tokenConfig[0].tokenType = TokenType.WITH_RATE;
        tokenConfig[1].tokenType = TokenType.WITH_RATE;
        tokenConfig[waDaiIdx].rateProvider = IRateProvider(address(waDAI));
        tokenConfig[waUsdcIdx].rateProvider = IRateProvider(address(waUSDC));

        PoolMock newPool = new PoolMock(IVault(address(vault)), "Yield-bearing Pool", "YIELDYBOI");

        factoryMock.registerTestPool(address(newPool), tokenConfig, poolHooksContract);

        vm.label(address(newPool), "yield-bearing pool");
        yieldBearingPool = address(newPool);

        vm.startPrank(bob);
        waDAI.approve(address(permit2), MAX_UINT256);
        permit2.approve(address(waDAI), address(router), type(uint160).max, type(uint48).max);
        permit2.approve(address(waDAI), address(batchRouter), type(uint160).max, type(uint48).max);
        waUSDC.approve(address(permit2), MAX_UINT256);
        permit2.approve(address(waUSDC), address(router), type(uint160).max, type(uint48).max);
        permit2.approve(address(waUSDC), address(batchRouter), type(uint160).max, type(uint48).max);

        dai.mint(bob, yieldBearingPoolAmount);
        dai.approve(address(waDAI), yieldBearingPoolAmount);
        waDAI.deposit(yieldBearingPoolAmount, bob);

        usdc.mint(bob, yieldBearingPoolAmount);
        usdc.approve(address(waUSDC), yieldBearingPoolAmount);
        waUSDC.deposit(yieldBearingPoolAmount, bob);

        _initPool(
            yieldBearingPool,
            [yieldBearingPoolAmount, yieldBearingPoolAmount].toMemoryArray(),
            yieldBearingPoolAmount * 2 - MIN_BPT
        );
        vm.stopPrank();
    }

    function testSwapPreconditions() public view {
        // bob should have the full yieldBearingPool BPT.
        assertEq(
            IERC20(yieldBearingPool).balanceOf(bob),
            yieldBearingPoolAmount * 2 - MIN_BPT,
            "Wrong yield-bearing pool BPT amount"
        );

        (IERC20[] memory tokens, , uint256[] memory balancesRaw, ) = vault.getPoolTokenInfo(yieldBearingPool);
        // The yield-bearing pool should have `yieldBearingPoolAmount` of both tokens.
        assertEq(address(tokens[waDaiIdx]), address(waDAI), "Wrong yield-bearing pool token (waDAI)");
        assertEq(address(tokens[waUsdcIdx]), address(waUSDC), "Wrong yield-bearing pool token (waUSDC)");
        assertEq(balancesRaw[0], yieldBearingPoolAmount, "Wrong yield-bearing pool balance [0]");
        assertEq(balancesRaw[1], yieldBearingPoolAmount, "Wrong yield-bearing pool balance [1]");

        // Buffers should have zero liquidity.
        uint256 baseBalance;
        uint256 wrappedBalance;

        // The vault buffers should each have `bufferAmount` of their respective tokens.
        (baseBalance, wrappedBalance) = vault.getBufferBalance(IERC4626(waDAI));
        assertEq(baseBalance, 0, "Wrong waDAI buffer balance for base token");
        assertEq(wrappedBalance, 0, "Wrong waDAI buffer balance for wrapped token");

        (baseBalance, wrappedBalance) = vault.getBufferBalance(IERC4626(waUSDC));
        assertEq(baseBalance, 0, "Wrong waUSDC buffer balance for base token");
        assertEq(wrappedBalance, 0, "Wrong waUSDC buffer balance for wrapped token");
    }

    function testYieldBearingPoolSwapWithoutBufferExactIn() public {
        IBatchRouter.SwapPathExactAmountIn[] memory paths = _buildExactInPaths(swapAmount);

        vm.prank(alice);
        (uint256[] memory pathAmountsOut, address[] memory tokensOut, uint256[] memory amountsOut) = batchRouter
            .swapExactIn(paths, MAX_UINT256, false, bytes(""));

        _verifySwapResult(pathAmountsOut, tokensOut, amountsOut, swapAmount, SwapKind.EXACT_IN);
    }

    function testYieldBearingPoolSwapWithoutBufferExactOut() public {
        IBatchRouter.SwapPathExactAmountOut[] memory paths = _buildExactOutPaths(swapAmount);

        vm.prank(alice);
        (uint256[] memory pathAmountsIn, address[] memory tokensIn, uint256[] memory amountsIn) = batchRouter
            .swapExactOut(paths, MAX_UINT256, false, bytes(""));

        _verifySwapResult(pathAmountsIn, tokensIn, amountsIn, swapAmount, SwapKind.EXACT_OUT);
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
        steps[1] = IBatchRouter.SwapPathStep({ pool: yieldBearingPool, tokenOut: waUSDC, isBuffer: false });
        steps[2] = IBatchRouter.SwapPathStep({ pool: address(waUSDC), tokenOut: usdc, isBuffer: true });

        paths[0] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: dai,
            steps: steps,
            exactAmountIn: amount,
            minAmountOut: amount - 1 // rebalance tests are a wei off
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
        steps[1] = IBatchRouter.SwapPathStep({ pool: yieldBearingPool, tokenOut: waUSDC, isBuffer: false });
        steps[2] = IBatchRouter.SwapPathStep({ pool: address(waUSDC), tokenOut: usdc, isBuffer: true });

        paths[0] = IBatchRouter.SwapPathExactAmountOut({
            tokenIn: dai,
            steps: steps,
            maxAmountIn: amount,
            exactAmountOut: amount
        });
    }

    function _verifySwapResult(
        uint256[] memory paths,
        address[] memory tokens,
        uint256[] memory amounts,
        uint256 expectedDelta,
        SwapKind kind
    ) private view {
        assertEq(paths.length, 1, "Incorrect output array length");

        assertEq(paths.length, tokens.length, "Output array length mismatch");
        assertEq(tokens.length, amounts.length, "Output array length mismatch");

        // Check results
        assertApproxEqAbs(paths[0], expectedDelta, 1, "Wrong path count");
        assertApproxEqAbs(amounts[0], expectedDelta, 1, "Wrong amounts count");
        assertEq(tokens[0], kind == SwapKind.EXACT_IN ? address(usdc) : address(dai), "Wrong token for SwapKind");

        // Tokens were transferred
        assertApproxEqAbs(dai.balanceOf(alice), defaultBalance - expectedDelta, 1, "Wrong ending balance of DAI");
        assertApproxEqAbs(usdc.balanceOf(alice), defaultBalance + expectedDelta, 1, "Wrong ending balance of USDC");

        uint256[] memory balancesRaw;

        (uint256 daiIdx, uint256 usdcIdx) = getSortedIndexes(address(waDAI), address(waUSDC));
        (, , balancesRaw, ) = vault.getPoolTokenInfo(yieldBearingPool);
        assertEq(balancesRaw[daiIdx], yieldBearingPoolAmount + expectedDelta, "Wrong yield-bearing pool DAI balance");
        assertEq(balancesRaw[usdcIdx], yieldBearingPoolAmount - expectedDelta, "Wrong yield-bearing pool USDC balance");

        // Buffers should have 0 liquidity, since they were not initialized.
        uint256 baseBalance;
        uint256 wrappedBalance;
        (baseBalance, wrappedBalance) = vault.getBufferBalance(IERC4626(waDAI));
        assertEq(baseBalance, 0, "DAI buffer pool base balance is not 0");
        assertEq(wrappedBalance, 0, "DAI buffer pool wrapped balance is not 0");

        (baseBalance, wrappedBalance) = vault.getBufferBalance(IERC4626(waUSDC));
        assertEq(baseBalance, 0, "USDC buffer pool base balance is not 0");
        assertEq(wrappedBalance, 0, "USDC buffer pool wrapped balance is not 0");
    }
}
