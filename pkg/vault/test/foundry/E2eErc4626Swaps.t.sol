// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IBatchRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IBatchRouter.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { ScalingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ScalingHelpers.sol";

import { BaseERC4626BufferTest } from "./utils/BaseERC4626BufferTest.sol";
import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract E2eErc4626SwapsTest is BaseERC4626BufferTest {
    using ArrayHelpers for *;
    using CastingHelpers for address[];
    using FixedPoint for uint256;
    using ScalingHelpers for uint256;

    uint256 internal constant minSwapAmount = 1e6;
    uint256 internal maxSwapAmount;

    function setUp() public virtual override {
        super.setUp();
        // Set the pool so we can measure the invariant with BaseVaultTest's getBalances().
        pool = erc4626Pool;

        maxSwapAmount = erc4626PoolInitialAmount.mulDown(25e16); // 25% of pool liquidity

        // Donate tokens to vault as a shortcut to change the pool balances without the need to pass through add/remove
        // liquidity operations. (No need to deal with BPTs, pranking LPs, guardrails, etc).
        _donateToVault();
    }

    function testDoUndoExactInSwapAmount__Fuzz(uint256 exactDaiAmountIn) public {
        DoUndoLocals memory testLocals;
        testLocals.shouldTestSwapAmount = true;

        _testDoUndoExactInBase(exactDaiAmountIn, testLocals);
    }

    function testDoUndoExactInLiquidity__Fuzz(uint256 liquidityWaDai, uint256 liquidityWaUsdc) public {
        DoUndoLocals memory testLocals;
        testLocals.shouldTestLiquidity = true;
        testLocals.liquidityWaDai = liquidityWaDai;
        testLocals.liquidityWaUsdc = liquidityWaUsdc;

        uint256 exactDaiAmountIn = maxSwapAmount;

        _testDoUndoExactInBase(exactDaiAmountIn, testLocals);
    }

    function testDoUndoExactOutSwapAmount__Fuzz(uint256 exactUsdcAmountOut) public {
        DoUndoLocals memory testLocals;
        testLocals.shouldTestSwapAmount = true;

        _testDoUndoExactOutBase(exactUsdcAmountOut, testLocals);
    }

    function testDoUndoExactOutLiquidity__Fuzz(uint256 liquidityWaDai, uint256 liquidityWaUsdc) public {
        DoUndoLocals memory testLocals;
        testLocals.shouldTestLiquidity = true;
        testLocals.liquidityWaDai = liquidityWaDai;
        testLocals.liquidityWaUsdc = liquidityWaUsdc;

        uint256 exactUsdcAmountOut = maxSwapAmount;

        _testDoUndoExactOutBase(exactUsdcAmountOut, testLocals);
    }

    struct DoUndoLocals {
        bool shouldTestLiquidity;
        bool shouldTestSwapAmount;
        bool shouldTestFee;
        uint256 liquidityWaDai;
        uint256 liquidityWaUsdc;
        uint256 poolSwapFeePercentage;
    }

    function _testDoUndoExactInBase(uint256 exactDaiAmountIn, DoUndoLocals memory testLocals) private {
        if (testLocals.shouldTestLiquidity) {
            _setPoolBalances(testLocals.liquidityWaDai, testLocals.liquidityWaUsdc);
        }

        maxSwapAmount = _getMaxSwapAmount();

        if (testLocals.shouldTestSwapAmount) {
            exactDaiAmountIn = bound(exactDaiAmountIn, minSwapAmount, maxSwapAmount);
        } else {
            exactDaiAmountIn = maxSwapAmount;
        }

        TestBalances memory balancesBefore = _getTestBalances(bob);

        IBatchRouter.SwapPathExactAmountIn[] memory pathsDo = _buildExactInPaths(dai, exactDaiAmountIn);
        vm.prank(bob);
        (uint256[] memory pathAmountsOut, , ) = batchRouter.swapExactIn(pathsDo, MAX_UINT256, false, bytes(""));

        IBatchRouter.SwapPathExactAmountIn[] memory pathsUndo = _buildExactInPaths(usdc, pathAmountsOut[0]);
        vm.prank(bob);
        batchRouter.swapExactIn(pathsUndo, MAX_UINT256, false, bytes(""));

        TestBalances memory balancesAfter = _getTestBalances(bob);

        _checkUserBalancesAndPoolInvariant(balancesBefore, balancesAfter);
    }

    function _testDoUndoExactOutBase(uint256 exactUsdcAmountOut, DoUndoLocals memory testLocals) private {
        if (testLocals.shouldTestLiquidity) {
            _setPoolBalances(testLocals.liquidityWaDai, testLocals.liquidityWaUsdc);
        }

        maxSwapAmount = _getMaxSwapAmount();

        if (testLocals.shouldTestSwapAmount) {
            exactUsdcAmountOut = bound(exactUsdcAmountOut, minSwapAmount, maxSwapAmount);
        } else {
            exactUsdcAmountOut = maxSwapAmount;
        }

        TestBalances memory balancesBefore = _getTestBalances(bob);

        IBatchRouter.SwapPathExactAmountOut[] memory pathsDo = _buildExactOutPaths(usdc, exactUsdcAmountOut);
        vm.prank(bob);
        (uint256[] memory pathAmountsIn, , ) = batchRouter.swapExactOut(pathsDo, MAX_UINT256, false, bytes(""));

        IBatchRouter.SwapPathExactAmountOut[] memory pathsUndo = _buildExactOutPaths(dai, pathAmountsIn[0]);
        vm.prank(bob);
        batchRouter.swapExactOut(pathsUndo, MAX_UINT256, false, bytes(""));

        TestBalances memory balancesAfter = _getTestBalances(bob);

        _checkUserBalancesAndPoolInvariant(balancesBefore, balancesAfter);
    }

    function _checkUserBalancesAndPoolInvariant(
        TestBalances memory balancesBefore,
        TestBalances memory balancesAfter
    ) private pure {
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

        // We cannot use MAX_UINT128 as maxAmountIn, since the maxAmountIn is paid upfront. We need to use a value that
        // "Bob" can pay.
        paths[0] = IBatchRouter.SwapPathExactAmountOut({
            tokenIn: tokenIn,
            steps: steps,
            maxAmountIn: dai.balanceOf(bob) / 10,
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

    function _setPoolBalances(uint256 liquidityWaDai, uint256 liquidityWaUsdc) private {
        // 1% to 10000% of erc4626 initial pool liquidity.
        liquidityWaDai = bound(
            liquidityWaDai,
            erc4626PoolInitialAmount.mulDown(1e16),
            erc4626PoolInitialAmount.mulDown(10000e16)
        );
        liquidityWaDai = waDAI.convertToShares(liquidityWaDai);
        // 1% to 10000% of erc4626 initial pool liquidity.
        liquidityWaUsdc = bound(
            liquidityWaUsdc,
            erc4626PoolInitialAmount.mulDown(1e16),
            erc4626PoolInitialAmount.mulDown(10000e16)
        );
        liquidityWaUsdc = waUSDC.convertToShares(liquidityWaUsdc);

        uint256[] memory newPoolBalance = new uint256[](2);
        newPoolBalance[waDaiIdx] = liquidityWaDai;
        newPoolBalance[waUsdcIdx] = liquidityWaUsdc;

        uint256[] memory newPoolBalanceLiveScaled18 = new uint256[](2);
        newPoolBalanceLiveScaled18[waDaiIdx] = liquidityWaDai.toScaled18ApplyRateRoundUp(1, waDAI.getRate());
        newPoolBalanceLiveScaled18[waUsdcIdx] = liquidityWaUsdc.toScaled18ApplyRateRoundUp(1, waUSDC.getRate());

        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(pool);
        vault.manualSetPoolTokensAndBalances(pool, tokens, newPoolBalance, newPoolBalanceLiveScaled18);
        // Updates pool data with latest token rates.
        vault.loadPoolDataUpdatingBalancesAndYieldFees(pool, Rounding.ROUND_DOWN);
    }

    function _getMaxSwapAmount() private view returns (uint256 newMaxSwapAmount) {
        // In the case of an yield-bearing pool, lastBalancesLiveScaled18 is the same as the balances in underlying
        // terms, if underlying and wrapped tokens have 18 decimals.
        (, , , uint256[] memory underlyingBalances) = vault.getPoolTokenInfo(pool);
        uint256 smallerBalance = underlyingBalances[waDaiIdx] < underlyingBalances[waUsdcIdx]
            ? underlyingBalances[waDaiIdx]
            : underlyingBalances[waUsdcIdx];
        return smallerBalance.mulDown(25e16); // 25% of the smallest pool liquidity.
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

    function _donateToVault() internal virtual {
        uint256 underlyingToDeposit = 10000 * erc4626PoolInitialAmount;
        dai.mint(address(vault), underlyingToDeposit);
        usdc.mint(address(vault), underlyingToDeposit);

        vm.startPrank(address(vault));
        dai.approve(address(waDAI), underlyingToDeposit);
        uint256 mintedWaDAI = waDAI.deposit(underlyingToDeposit, address(vault));

        usdc.approve(address(waUSDC), underlyingToDeposit);
        uint256 mintedWaUSDC = waUSDC.deposit(underlyingToDeposit, address(vault));
        vm.stopPrank();

        // Override vault liquidity, to make sure the extra liquidity is registered.
        vault.manualSetReservesOf(IERC20(address(waDAI)), mintedWaDAI);
        vault.manualSetReservesOf(IERC20(address(waUSDC)), mintedWaUSDC);
    }
}
