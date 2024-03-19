// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { TokenConfig, TokenType } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IBatchRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IBatchRouter.sol";
import { SwapKind } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ERC4626TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC4626TestToken.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";

import { ERC4626BufferPoolFactoryMock } from "./utils/ERC4626BufferPoolFactoryMock.sol";
import { ERC4626BufferPoolMock } from "./utils/ERC4626BufferPoolMock.sol";
import { PoolMock } from "../../contracts/test/PoolMock.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract BufferSwapTest is BaseVaultTest {
    using ArrayHelpers for *;

    ERC4626TestToken internal waDAI;
    ERC4626TestToken internal waUSDC;

    ERC4626BufferPoolFactoryMock bufferFactory;

    // For two-token pools with waDAI/waUSDC, keep track of sorted token order.
    uint256 internal waDaiIdx;
    uint256 internal waUsdcIdx;

    address internal waDAIBufferPool;
    address internal waUSDCBufferPool;

    address internal boostedPool;

    // `defaultAmount` from BaseVaultTest (e.g., 1,000), corresponds to the funding of the buffer.
    // We will swap with 10% of the buffer
    uint256 internal swapAmount = defaultAmount / 10;
    // The boosted pool will have 10x the liquidity of the buffer
    uint256 internal boostedPoolAmount = defaultAmount * 10;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        waDAI = new ERC4626TestToken(dai, "Wrapped aDAI", "waDAI", 18);
        // "USDC" is deliberately 18 decimals to test one thing at a time.
        waUSDC = new ERC4626TestToken(usdc, "Wrapped aUSDC", "waUSDC", 18);

        bufferFactory = new ERC4626BufferPoolFactoryMock(vault, 365 days);

        (waDaiIdx, waUsdcIdx) = getSortedIndexes(address(waDAI), address(waUSDC));

        initializeBuffers();
        initializeBoostedPool();
    }

    function initializeBuffers() private {
        // Create and fund buffer pools
        dai.mint(address(waDAI), defaultAmount);
        waDAI.mint(defaultAmount, lp);
        usdc.mint(address(waUSDC), defaultAmount);
        waUSDC.mint(defaultAmount, lp);

        waDAIBufferPool = bufferFactory.createMocked(waDAI);
        waUSDCBufferPool = bufferFactory.createMocked(waUSDC);

        vm.startPrank(lp);
        waDAI.approve(address(vault), MAX_UINT256);
        _initPool(waDAIBufferPool, [defaultAmount, defaultAmount].toMemoryArray(), defaultAmount * 2 - MIN_BPT);
        waUSDC.approve(address(vault), MAX_UINT256);
        _initPool(waUSDCBufferPool, [defaultAmount, defaultAmount].toMemoryArray(), defaultAmount * 2 - MIN_BPT);
        vm.stopPrank();
    }

    function initializeBoostedPool() private {
        TokenConfig[] memory tokenConfig = new TokenConfig[](2);
        tokenConfig[waDaiIdx].token = IERC20(waDAI);
        tokenConfig[waUsdcIdx].token = IERC20(waUSDC);
        tokenConfig[0].tokenType = TokenType.ERC4626;
        tokenConfig[1].tokenType = TokenType.ERC4626;

        PoolMock newPool = new PoolMock(IVault(address(vault)), "Boosted Pool", "BOOSTYBOI");

        factoryMock.registerTestPool(address(newPool), tokenConfig);

        vm.label(address(newPool), "boosted pool");
        boostedPool = address(newPool);

        dai.mint(address(waDAI), boostedPoolAmount);
        waDAI.mint(boostedPoolAmount, bob);
        usdc.mint(address(waUSDC), boostedPoolAmount);
        waUSDC.mint(boostedPoolAmount, bob);

        vm.startPrank(bob);
        waDAI.approve(address(vault), MAX_UINT256);
        waUSDC.approve(address(vault), MAX_UINT256);

        _initPool(boostedPool, [boostedPoolAmount, boostedPoolAmount].toMemoryArray(), boostedPoolAmount * 2 - MIN_BPT);
        vm.stopPrank();
    }

    function testSwapPreconditions() public {
        // bob should have the full boostedPool BPT.
        assertEq(IERC20(boostedPool).balanceOf(bob), boostedPoolAmount * 2 - MIN_BPT, "Wrong boosted pool BPT amount");

        (IERC20[] memory tokens, , uint256[] memory balancesRaw, , ) = vault.getPoolTokenInfo(boostedPool);
        // The boosted pool should have `boostedPoolAmount` of both tokens.
        assertEq(address(tokens[waDaiIdx]), address(waDAI), "Wrong boosted pool token (waDAI)");
        assertEq(address(tokens[waUsdcIdx]), address(waUSDC), "Wrong boosted pool token (waUSDC)");
        assertEq(balancesRaw[0], boostedPoolAmount, "Wrong boosted pool balance [0]");
        assertEq(balancesRaw[1], boostedPoolAmount, "Wrong boosted pool balance [1]");

        // lp should have all the buffer BPT.
        assertEq(
            IERC20(waDAIBufferPool).balanceOf(lp),
            defaultAmount * 2 - MIN_BPT,
            "Wrong DAI buffer pool BPT amount"
        );
        assertEq(
            IERC20(waUSDCBufferPool).balanceOf(lp),
            defaultAmount * 2 - MIN_BPT,
            "Wrong USDC buffer pool BPT amount"
        );

        // The buffer pools should each have `defaultAmount` of their respective tokens.
        (uint256 wrappedIdx, uint256 baseIdx) = getSortedIndexes(address(waDAI), address(dai));
        (tokens, , balancesRaw, , ) = vault.getPoolTokenInfo(waDAIBufferPool);
        assertEq(address(tokens[wrappedIdx]), address(waDAI), "Wrong DAI buffer pool wrapped token");
        assertEq(address(tokens[baseIdx]), address(dai), "Wrong DAI buffer pool base token");
        assertEq(balancesRaw[0], defaultAmount, "Wrong waDAI buffer pool balance [0]");
        assertEq(balancesRaw[1], defaultAmount, "Wrong waDAI buffer pool balance [1]");

        (wrappedIdx, baseIdx) = getSortedIndexes(address(waUSDC), address(usdc));
        (tokens, , balancesRaw, , ) = vault.getPoolTokenInfo(waUSDCBufferPool);
        assertEq(address(tokens[wrappedIdx]), address(waUSDC), "Wrong USDC buffer pool wrapped token");
        assertEq(address(tokens[baseIdx]), address(usdc), "Wrong USDC buffer pool base token");
        assertEq(balancesRaw[0], defaultAmount, "Wrong waUSDC buffer pool balance [0]");
        assertEq(balancesRaw[1], defaultAmount, "Wrong waUSDC buffer pool balance [1]");
    }

    function testBoostedPoolSwapExactIn() public {
        IBatchRouter.SwapPathExactAmountIn[] memory paths = _buildExactInPaths(swapAmount);

        vm.prank(alice);
        (uint256[] memory pathAmountsOut, address[] memory tokensOut, uint256[] memory amountsOut) = batchRouter
            .swapExactIn(paths, MAX_UINT256, false, bytes(""));

        _verifySwapResult(pathAmountsOut, tokensOut, amountsOut, swapAmount, SwapKind.EXACT_IN, true);
    }

    function testBoostedPoolSwapExactOut() public {
        IBatchRouter.SwapPathExactAmountOut[] memory paths = _buildExactOutPaths(swapAmount);

        vm.prank(alice);
        (uint256[] memory pathAmountsIn, address[] memory tokensIn, uint256[] memory amountsIn) = batchRouter
            .swapExactOut(paths, MAX_UINT256, false, bytes(""));

        _verifySwapResult(pathAmountsIn, tokensIn, amountsIn, swapAmount, SwapKind.EXACT_OUT, true);
    }

    function testBoostedPoolSwapTooLarge() public {
        // We have `defaultAmount` of base and wrapped token liquidity in the buffer.
        // If we swap with an amount greater than the total liquidity, we cannot use the buffer.

        uint256 tooLargeSwapAmount = defaultAmount * 2 + swapAmount;

        IBatchRouter.SwapPathExactAmountIn[] memory paths = _buildExactInPaths(tooLargeSwapAmount);

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.BeforeSwapHookFailed.selector));
        vm.prank(alice);
        batchRouter.swapExactIn(paths, MAX_UINT256, false, bytes(""));
    }

    function testBoostedPoolSwapSimpleRebalance() public {
        // We want to unbalance the pool such that the "low balance" = swapAmount
        uint256 amountToUnwrap = defaultAmount - swapAmount;
        ERC4626BufferPoolMock(waDAIBufferPool).unbalanceThePool(amountToUnwrap, SwapKind.EXACT_IN);

        // Check that it is unbalanced
        (uint256 wrappedIdx, uint256 baseIdx) = getSortedIndexes(address(waDAI), address(dai));
        (, , uint256[] memory balancesRaw, , ) = vault.getPoolTokenInfo(waDAIBufferPool);

        assertEq(balancesRaw[wrappedIdx], swapAmount, "Wrong waDAI buffer pool balance (waDAI)");
        assertEq(balancesRaw[baseIdx], defaultAmount + amountToUnwrap, "Wrong waDAI buffer pool balance (DAI)");

        // We are swapping DAI for waDAI, and the balances are: DAI: 1900, waDAI: 100.
        // With Linear Math, we will be withdrawing the trade amount of the wrapped token.
        // With a trade amount of 100 DAI in/100 waDAI out, the ending balances would be 2000/0.

        // If we perform the swap with *twice* the available wrapped balance, we will not have enough waDAI.
        // The pool should detect this, rebalance to 50/50, then perform the trade.
        // Afterward then, the balances should be the same as if the pool were balanced: 1200/800
        IBatchRouter.SwapPathExactAmountIn[] memory paths = _buildExactInPaths(swapAmount * 2);

        vm.prank(alice);
        (uint256[] memory pathAmountsOut, address[] memory tokensOut, uint256[] memory amountsOut) = batchRouter
            .swapExactIn(paths, MAX_UINT256, false, bytes(""));

        // It should now be balanced (except for the trade)
        _verifySwapResult(pathAmountsOut, tokensOut, amountsOut, swapAmount * 2, SwapKind.EXACT_IN, false);
    }

    function _buildExactInPaths(
        uint256 amount
    ) private view returns (IBatchRouter.SwapPathExactAmountIn[] memory paths) {
        IBatchRouter.SwapPathStep[] memory steps = new IBatchRouter.SwapPathStep[](3);
        paths = new IBatchRouter.SwapPathExactAmountIn[](1);

        // "Transparent" USDC for DAI swap with boosted pool, which holds only wrapped tokens.
        // Since this is exact in, swaps will be executed in the order given.
        // Pre-swap through DAI buffer to get waDAI, then main swap waDAI for waUSDC in the boosted pool,
        // and finally post-swap the waUSDC through the USDC buffer to calculate the USDC amount out.
        // The only token transfers are DAI in (given) and USDC out (calculated).
        steps[0] = IBatchRouter.SwapPathStep({ pool: waDAIBufferPool, tokenOut: waDAI });
        steps[1] = IBatchRouter.SwapPathStep({ pool: boostedPool, tokenOut: waUSDC });
        steps[2] = IBatchRouter.SwapPathStep({ pool: waUSDCBufferPool, tokenOut: usdc });

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

        // "Transparent" USDC for DAI swap with boosted pool, which holds only wrapped tokens.
        // Since this is exact out, swaps will be executed in reverse order (though we submit in logical order).
        // Pre-swap through the USDC buffer to get waUSDC, then main swap waUSDC for waDAI in the boosted pool,
        // and finally post-swap the waDAI for DAI through the DAI buffer to calculate the DAI amount in.
        // The only token transfers are DAI in (calculated) and USDC out (given).
        steps[0] = IBatchRouter.SwapPathStep({ pool: waDAIBufferPool, tokenOut: waDAI });
        steps[1] = IBatchRouter.SwapPathStep({ pool: boostedPool, tokenOut: waUSDC });
        steps[2] = IBatchRouter.SwapPathStep({ pool: waUSDCBufferPool, tokenOut: usdc });

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
        SwapKind kind,
        bool balanced
    ) private {
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

        if (balanced) {
            uint256[] memory balancesRaw;

            (uint256 daiIdx, uint256 usdcIdx) = getSortedIndexes(address(waDAI), address(waUSDC));
            (, , balancesRaw, , ) = vault.getPoolTokenInfo(boostedPool);
            assertEq(balancesRaw[daiIdx], boostedPoolAmount + expectedDelta, "Wrong boosted pool DAI balance");
            assertEq(balancesRaw[usdcIdx], boostedPoolAmount - expectedDelta, "Wrong boosted pool DAI balance");

            (uint256 wrappedIdx, uint256 baseIdx) = getSortedIndexes(address(waDAI), address(dai));
            (, , balancesRaw, , ) = vault.getPoolTokenInfo(waDAIBufferPool);
            assertEq(balancesRaw[baseIdx], defaultAmount + expectedDelta, "Wrong DAI buffer pool base balance");
            assertEq(balancesRaw[wrappedIdx], defaultAmount - expectedDelta, "Wrong DAI buffer pool wrapped balance");

            (wrappedIdx, baseIdx) = getSortedIndexes(address(waUSDC), address(usdc));
            (, , balancesRaw, , ) = vault.getPoolTokenInfo(waUSDCBufferPool);
            assertEq(balancesRaw[baseIdx], defaultAmount - expectedDelta, "Wrong USDC buffer pool base balance");
            assertEq(balancesRaw[wrappedIdx], defaultAmount + expectedDelta, "Wrong USDC buffer pool wrapped balance");
        }
    }
}
