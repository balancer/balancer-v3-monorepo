// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IBatchRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IBatchRouter.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";

import { BaseERC4626BufferTest } from "./utils/BaseERC4626BufferTest.sol";
import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract E2eErc4626SwapsTest is BaseERC4626BufferTest {
    using ArrayHelpers for *;
    using CastingHelpers for address[];

    function setUp() public override {
        super.setUp();
        // Set the pool so we can measure the invariant with BaseVaultTest's getBalances().
        pool = erc4626Pool;
    }

    function testDoUndoExactInSwapAmount__Fuzz(uint256 exactDaiAmountIn) public {
        // From minimum swap amount to 30% of pool liquidity.
        exactDaiAmountIn = bound(exactDaiAmountIn, 1e6, (3 * erc4626PoolInitialAmount) / 10);

        TestBalances memory balancesBefore = _getTestBalances(bob);

        IBatchRouter.SwapPathExactAmountIn[] memory pathsDo = _buildExactInPaths(dai, exactDaiAmountIn);
        vm.prank(bob);
        (uint256[] memory pathAmountsOut, , ) = batchRouter.swapExactIn(pathsDo, MAX_UINT256, false, bytes(""));

        IBatchRouter.SwapPathExactAmountIn[] memory pathsUndo = _buildExactInPaths(usdc, pathAmountsOut[0]);
        vm.prank(bob);
        batchRouter.swapExactIn(pathsUndo, MAX_UINT256, false, bytes(""));

        TestBalances memory balancesAfter = _getTestBalances(bob);

        // User balances.
        assertLe(
            balancesAfter.balances.bobTokens[balancesAfter.daiIdx],
            balancesBefore.balances.bobTokens[balancesBefore.daiIdx],
            "DAI balance is incorrect"
        );
        assertLe(
            balancesAfter.balances.bobTokens[balancesAfter.usdcIdx],
            balancesBefore.balances.bobTokens[balancesBefore.usdcIdx],
            "USDC balance is incorrect"
        );

        // Pool invariant.
        assertGe(
            balancesAfter.balances.poolInvariant,
            balancesBefore.balances.poolInvariant,
            "Pool invariant decreased"
        );
    }

    function testDoUndoExactOutSwapAmount__Fuzz(uint256 exactUsdcAmountOut) public {
        // From minimum swap amount to 30% of pool liquidity.
        exactUsdcAmountOut = bound(exactUsdcAmountOut, 1e6, (3 * erc4626PoolInitialAmount) / 10);

        TestBalances memory balancesBefore = _getTestBalances(bob);

        IBatchRouter.SwapPathExactAmountOut[] memory pathsDo = _buildExactOutPaths(usdc, exactUsdcAmountOut);
        vm.prank(bob);
        (uint256[] memory pathAmountsIn, , ) = batchRouter.swapExactOut(pathsDo, MAX_UINT256, false, bytes(""));

        IBatchRouter.SwapPathExactAmountOut[] memory pathsUndo = _buildExactOutPaths(dai, pathAmountsIn[0]);
        vm.prank(bob);
        batchRouter.swapExactOut(pathsUndo, MAX_UINT256, false, bytes(""));

        TestBalances memory balancesAfter = _getTestBalances(bob);

        // User balances.
        assertLe(
            balancesAfter.balances.bobTokens[balancesAfter.daiIdx],
            balancesBefore.balances.bobTokens[balancesBefore.daiIdx],
            "DAI balance is incorrect"
        );
        assertLe(
            balancesAfter.balances.bobTokens[balancesAfter.usdcIdx],
            balancesBefore.balances.bobTokens[balancesBefore.usdcIdx],
            "USDC balance is incorrect"
        );

        // Pool invariant.
        assertGe(
            balancesAfter.balances.poolInvariant,
            balancesBefore.balances.poolInvariant,
            "Pool invariant decreased"
        );
    }

    function _buildExactInPaths(
        IERC20 tokenIn,
        uint256 amountIn
    ) private view returns (IBatchRouter.SwapPathExactAmountIn[] memory paths) {
        IBatchRouter.SwapPathStep[] memory steps = new IBatchRouter.SwapPathStep[](3);
        paths = new IBatchRouter.SwapPathExactAmountIn[](1);

        // Since this is exact in, swaps will be executed in the order given.
        // Pre-swap through DAI buffer to get waDAI, then main swap waDAI for waUSDC in the yield-bearing pool,
        // and finally post-swap the waUSDC through the USDC buffer to calculate the USDC amount out.
        // The only token transfers are DAI in (given) and USDC out (calculated).
        if (tokenIn == dai) {
            steps[0] = IBatchRouter.SwapPathStep({ pool: address(waDAI), tokenOut: waDAI, isBuffer: true });
            steps[1] = IBatchRouter.SwapPathStep({ pool: erc4626Pool, tokenOut: waUSDC, isBuffer: false });
            steps[2] = IBatchRouter.SwapPathStep({ pool: address(waUSDC), tokenOut: usdc, isBuffer: true });
        } else {
            steps[0] = IBatchRouter.SwapPathStep({ pool: address(waUSDC), tokenOut: waUSDC, isBuffer: true });
            steps[1] = IBatchRouter.SwapPathStep({ pool: erc4626Pool, tokenOut: waDAI, isBuffer: false });
            steps[2] = IBatchRouter.SwapPathStep({ pool: address(waDAI), tokenOut: dai, isBuffer: true });
        }

        paths[0] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: tokenIn,
            steps: steps,
            exactAmountIn: amountIn,
            minAmountOut: 1
        });
    }

    function _buildExactOutPaths(
        IERC20 tokenOut,
        uint256 amountOut
    ) private view returns (IBatchRouter.SwapPathExactAmountOut[] memory paths) {
        IBatchRouter.SwapPathStep[] memory steps = new IBatchRouter.SwapPathStep[](3);
        paths = new IBatchRouter.SwapPathExactAmountOut[](1);
        IERC20 tokenIn = tokenOut == dai ? usdc : dai;

        // Since this is exact out, swaps will be executed in reverse order (though we submit in logical order).
        // Pre-swap through the USDC buffer to get waUSDC, then main swap waUSDC for waDAI in the yield-bearing pool,
        // and finally post-swap the waDAI for DAI through the DAI buffer to calculate the DAI amount in.
        // The only token transfers are DAI in (calculated) and USDC out (given).
        if (tokenIn == dai) {
            steps[0] = IBatchRouter.SwapPathStep({ pool: address(waDAI), tokenOut: waDAI, isBuffer: true });
            steps[1] = IBatchRouter.SwapPathStep({ pool: erc4626Pool, tokenOut: waUSDC, isBuffer: false });
            steps[2] = IBatchRouter.SwapPathStep({ pool: address(waUSDC), tokenOut: usdc, isBuffer: true });
        } else {
            steps[0] = IBatchRouter.SwapPathStep({ pool: address(waUSDC), tokenOut: waUSDC, isBuffer: true });
            steps[1] = IBatchRouter.SwapPathStep({ pool: erc4626Pool, tokenOut: waDAI, isBuffer: false });
            steps[2] = IBatchRouter.SwapPathStep({ pool: address(waDAI), tokenOut: dai, isBuffer: true });
        }

        // We cannot use MAX_UINT128 as maxAmountIn, since the maxAmountIN is paid upfront.
        paths[0] = IBatchRouter.SwapPathExactAmountOut({
            tokenIn: tokenIn,
            steps: steps,
            maxAmountIn: 2 * amountOut,
            exactAmountOut: amountOut
        });
    }

    struct BufferBalances {
        uint256 underlying;
        uint256 wrapped;
    }

    struct TestBalances {
        BaseVaultTest.Balances balances;
        BufferBalances waUSDCBuffer;
        BufferBalances waDAIBuffer;
        uint256 daiIdx;
        uint256 usdcIdx;
        uint256 waDaiIdx;
        uint256 waUsdcIdx;
    }

    function _getTestBalances(address sender) private view returns (TestBalances memory testBalances) {
        IERC20[] memory tokenArray = [address(dai), address(usdc), address(waDAI), address(waUSDC)]
            .toMemoryArray()
            .asIERC20();
        testBalances.balances = getBalances(sender, tokenArray);

        (uint256 waDAIBufferBalanceUnderlying, uint256 waDAIBufferBalanceWrapped) = vault.getBufferBalance(waDAI);
        testBalances.waDAIBuffer.underlying = waDAIBufferBalanceUnderlying;
        testBalances.waDAIBuffer.wrapped = waDAIBufferBalanceWrapped;

        (uint256 waUSDCBufferBalanceUnderlying, uint256 waUSDCBufferBalanceWrapped) = vault.getBufferBalance(waUSDC);
        testBalances.waUSDCBuffer.underlying = waUSDCBufferBalanceUnderlying;
        testBalances.waUSDCBuffer.wrapped = waUSDCBufferBalanceWrapped;

        // The index of each token is defined by the order of tokenArray, defined in this function.
        testBalances.daiIdx = 0;
        testBalances.usdcIdx = 1;
        testBalances.waDaiIdx = 2;
        testBalances.waUsdcIdx = 3;
    }
}
