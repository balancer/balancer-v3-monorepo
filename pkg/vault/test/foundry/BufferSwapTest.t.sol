// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { TokenConfig, TokenType } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IBatchRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IBatchRouter.sol";
import { SwapKind } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ERC4626TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC4626TestToken.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";

import { ERC4626BufferPoolFactory } from "../../contracts/factories/ERC4626BufferPoolFactory.sol";
import { PoolMock } from "../../contracts/test/PoolMock.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract BufferSwapTest is BaseVaultTest {
    using ArrayHelpers for *;

    ERC4626TestToken internal waDAI;
    ERC4626TestToken internal waUSDC;

    ERC4626BufferPoolFactory bufferFactory;

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

        bufferFactory = new ERC4626BufferPoolFactory(vault, 365 days);

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

        waDAIBufferPool = bufferFactory.create(waDAI, address(0), getSalt(address(waDAI)));
        waUSDCBufferPool = bufferFactory.create(waUSDC, address(0), getSalt(address(waUSDC)));

        IERC20[] memory daiBufferTokens = InputHelpers.sortTokens(
            [address(waDAI), address(dai)].toMemoryArray().asIERC20()
        );

        vm.startPrank(lp);
        waDAI.approve(address(vault), MAX_UINT256);

        router.initialize(
            address(waDAIBufferPool),
            daiBufferTokens,
            [defaultAmount, defaultAmount].toMemoryArray(),
            defaultAmount * 2 - MIN_BPT,
            false,
            bytes("")
        );

        IERC20[] memory usdcBufferTokens = InputHelpers.sortTokens(
            [address(waUSDC), address(usdc)].toMemoryArray().asIERC20()
        );

        waUSDC.approve(address(vault), MAX_UINT256);
        router.initialize(
            address(waUSDCBufferPool),
            usdcBufferTokens,
            [defaultAmount, defaultAmount].toMemoryArray(),
            defaultAmount * 2 - MIN_BPT,
            false,
            bytes("")
        );
        vm.stopPrank();
    }

    function initializeBoostedPool() private {
        TokenConfig[] memory tokenConfig = new TokenConfig[](2);
        tokenConfig[waDaiIdx].token = IERC20(waDAI);
        tokenConfig[waUsdcIdx].token = IERC20(waUSDC);
        tokenConfig[0].tokenType = TokenType.ERC4626;
        tokenConfig[1].tokenType = TokenType.ERC4626;

        PoolMock newPool = new PoolMock(
            IVault(address(vault)),
            "Boosted Pool",
            "BOOSTYBOI",
            tokenConfig,
            true,
            365 days,
            address(0)
        );
        vm.label(address(newPool), "boosted pool");
        boostedPool = address(newPool);

        dai.mint(address(waDAI), boostedPoolAmount);
        waDAI.mint(boostedPoolAmount, bob);
        usdc.mint(address(waUSDC), boostedPoolAmount);
        waUSDC.mint(boostedPoolAmount, bob);

        vm.startPrank(bob);
        waDAI.approve(address(vault), MAX_UINT256);
        waUSDC.approve(address(vault), MAX_UINT256);

        router.initialize(
            address(boostedPool),
            InputHelpers.sortTokens([address(waDAI), address(waUSDC)].toMemoryArray().asIERC20()),
            [boostedPoolAmount, boostedPoolAmount].toMemoryArray(),
            boostedPoolAmount * 2 - MIN_BPT,
            false,
            bytes("")
        );
        vm.stopPrank();
    }

    function testSwapPreconditions() public {
        // bob should have the full boostedPool BPT.
        assertEq(IERC20(boostedPool).balanceOf(bob), boostedPoolAmount * 2 - MIN_BPT, "Wrong boosted pool BPT amount");

        (IERC20[] memory tokens, , uint256[] memory balancesRaw, , ) = vault.getPoolTokenInfo(boostedPool);
        // The boosted pool should have `boostedPoolAmount` of both tokens.
        assertEq(address(tokens[waDaiIdx]), address(waDAI), "Wrong boosted pool token (waDAI)");
        assertEq(address(tokens[waUsdcIdx]), address(waUSDC), "Wrong boosted pool token (waUSDC)");
        assertEq(balancesRaw[0], boostedPoolAmount, "Wrong boosted pool balance");
        assertEq(balancesRaw[1], boostedPoolAmount, "Wrong boosted pool balance");

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
        IBatchRouter.SwapPathExactAmountIn[] memory paths = new IBatchRouter.SwapPathExactAmountIn[](1);
        IBatchRouter.SwapPathStep[] memory steps = new IBatchRouter.SwapPathStep[](3);

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
            exactAmountIn: swapAmount,
            minAmountOut: swapAmount
        });

        vm.prank(alice);
        (uint256[] memory pathAmountsOut, address[] memory tokensOut, uint256[] memory amountsOut) = batchRouter
            .swapExactIn(paths, MAX_UINT256, false, bytes(""));

        _verifySwapResult(pathAmountsOut, tokensOut, amountsOut, SwapKind.EXACT_IN);
    }

    function testBoostedPoolSwapExactOut() public {
        IBatchRouter.SwapPathExactAmountOut[] memory paths = new IBatchRouter.SwapPathExactAmountOut[](1);
        IBatchRouter.SwapPathStep[] memory steps = new IBatchRouter.SwapPathStep[](3);

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
            maxAmountIn: swapAmount,
            exactAmountOut: swapAmount
        });

        vm.prank(alice);
        (uint256[] memory pathAmountsIn, address[] memory tokensIn, uint256[] memory amountsIn) = batchRouter
            .swapExactOut(paths, MAX_UINT256, false, bytes(""));

        _verifySwapResult(pathAmountsIn, tokensIn, amountsIn, SwapKind.EXACT_OUT);
    }

    function _verifySwapResult(
        uint256[] memory paths,
        address[] memory tokens,
        uint256[] memory amounts,
        SwapKind kind
    ) private {
        assertEq(paths.length, 1, "Incorrect output array length");

        assertEq(paths.length, tokens.length, "Output array length mismatch");
        assertEq(tokens.length, amounts.length, "Output array length mismatch");

        // Check results
        assertEq(paths[0], swapAmount);
        assertEq(amounts[0], swapAmount);
        assertEq(tokens[0], kind == SwapKind.EXACT_IN ? address(usdc) : address(dai));

        // Tokens were transferred
        assertEq(dai.balanceOf(alice), defaultBalance - swapAmount);
        assertEq(usdc.balanceOf(alice), defaultBalance + swapAmount);
    }
}
