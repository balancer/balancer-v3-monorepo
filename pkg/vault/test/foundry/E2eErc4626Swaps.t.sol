// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IBatchRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IBatchRouter.sol";
import { IProtocolFeeController } from "@balancer-labs/v3-interfaces/contracts/vault/IProtocolFeeController.sol";
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

    // There are a lot of conversions in place to measure vault and user balances, which can bring some rounding
    // errors. Make sure this error is smaller than 10 wei.
    uint256 internal constant MAX_ERROR = 10;

    uint256 internal constant minSwapAmount = 1e6;
    uint256 internal maxSwapAmount;

    uint256 internal minPoolSwapFeePercentage;
    uint256 internal maxPoolSwapFeePercentage;

    address internal poolCreator;

    function setUp() public virtual override {
        super.setUp();
        // Set the pool so we can measure the invariant with BaseVaultTest's getBalances().
        pool = erc4626Pool;
        poolCreator = lp;

        maxSwapAmount = erc4626PoolInitialAmount.mulDown(25e16); // 25% of pool liquidity

        // Donate tokens to vault as a shortcut to change the pool balances without the need to pass through add/remove
        // liquidity operations. (No need to deal with BPTs, pranking LPs, guardrails, etc).
        _donateToVault();

        // Makes sure Bob has enough tokens to pay for DAI and WETH wraps.
        dai.mint(bob, 1000 * erc4626PoolInitialAmount);

        vm.deal(payable(bob), bob.balance + 1000 * erc4626PoolInitialAmount);
        vm.prank(bob);
        weth.deposit{ value: 1000 * erc4626PoolInitialAmount }();

        IProtocolFeeController feeController = vault.getProtocolFeeController();
        IAuthentication feeControllerAuth = IAuthentication(address(feeController));

        authorizer.grantRole(
            feeControllerAuth.getActionId(IProtocolFeeController.setGlobalProtocolSwapFeePercentage.selector),
            admin
        );

        vm.prank(poolCreator);
        // Set pool creator fee to 100%, so protocol + creator fees equals the total charged fees.
        feeController.setPoolCreatorSwapFeePercentage(pool, FixedPoint.ONE);

        minPoolSwapFeePercentage = IBasePool(pool).getMinimumSwapFeePercentage();
        maxPoolSwapFeePercentage = IBasePool(pool).getMaximumSwapFeePercentage();

        // These tests rely on a minimum fee to work; set something very small for pool mock.
        minPoolSwapFeePercentage = (minPoolSwapFeePercentage == 0 ? 1e12 : minPoolSwapFeePercentage);
        maxPoolSwapFeePercentage = (maxPoolSwapFeePercentage == 1e18 ? 10e16 : maxPoolSwapFeePercentage);
    }

    function testDoUndoExactInSwapAmount__Fuzz(uint256 exactDaiAmountIn) public {
        DoUndoLocals memory testLocals;
        testLocals.shouldTestSwapAmount = true;

        _testDoUndoExactInBase(exactDaiAmountIn, testLocals);
    }

    function testDoUndoExactInLiquidity__Fuzz(uint256 liquidityWaDai, uint256 liquidityWaWeth) public {
        DoUndoLocals memory testLocals;
        testLocals.shouldTestLiquidity = true;
        testLocals.liquidityWaDai = liquidityWaDai;
        testLocals.liquidityWaWeth = liquidityWaWeth;

        uint256 exactDaiAmountIn = maxSwapAmount;

        _testDoUndoExactInBase(exactDaiAmountIn, testLocals);
    }

    function testDoUndoExactInFees__Fuzz(uint256 poolSwapFeePercentage) public {
        DoUndoLocals memory testLocals;
        testLocals.shouldTestFee = true;
        testLocals.poolSwapFeePercentage = poolSwapFeePercentage;

        uint256 exactDaiAmountIn = maxSwapAmount;

        _testDoUndoExactInBase(exactDaiAmountIn, testLocals);
    }

    function testDoUndoExactInComplete__Fuzz(
        uint256 exactDaiAmountIn,
        uint256 poolSwapFeePercentage,
        uint256 liquidityWaDai,
        uint256 liquidityWaWeth
    ) public {
        DoUndoLocals memory testLocals;
        testLocals.shouldTestLiquidity = true;
        testLocals.shouldTestSwapAmount = true;
        testLocals.shouldTestFee = true;
        testLocals.liquidityWaDai = liquidityWaDai;
        testLocals.liquidityWaWeth = liquidityWaWeth;
        testLocals.poolSwapFeePercentage = poolSwapFeePercentage;

        _testDoUndoExactInBase(exactDaiAmountIn, testLocals);
    }

    function testDoUndoExactOutSwapAmount__Fuzz(uint256 exactWethAmountOut) public {
        DoUndoLocals memory testLocals;
        testLocals.shouldTestSwapAmount = true;

        _testDoUndoExactOutBase(exactWethAmountOut, testLocals);
    }

    function testDoUndoExactOutLiquidity__Fuzz(uint256 liquidityWaDai, uint256 liquidityWaWeth) public {
        DoUndoLocals memory testLocals;
        testLocals.shouldTestLiquidity = true;
        testLocals.liquidityWaDai = liquidityWaDai;
        testLocals.liquidityWaWeth = liquidityWaWeth;

        uint256 exactWethAmountOut = maxSwapAmount;

        _testDoUndoExactOutBase(exactWethAmountOut, testLocals);
    }

    function testDoUndoExactOutFees__Fuzz(uint256 poolSwapFeePercentage) public {
        DoUndoLocals memory testLocals;
        testLocals.shouldTestFee = true;
        testLocals.poolSwapFeePercentage = poolSwapFeePercentage;

        uint256 exactWethAmountOut = maxSwapAmount;

        _testDoUndoExactOutBase(exactWethAmountOut, testLocals);
    }

    function testDoUndoExactOutComplete__Fuzz(
        uint256 exactWethAmountOut,
        uint256 poolSwapFeePercentage,
        uint256 liquidityWaDai,
        uint256 liquidityWaWeth
    ) public {
        DoUndoLocals memory testLocals;
        testLocals.shouldTestLiquidity = true;
        testLocals.shouldTestSwapAmount = true;
        testLocals.shouldTestFee = true;
        testLocals.liquidityWaDai = liquidityWaDai;
        testLocals.liquidityWaWeth = liquidityWaWeth;
        testLocals.poolSwapFeePercentage = poolSwapFeePercentage;

        _testDoUndoExactOutBase(exactWethAmountOut, testLocals);
    }

    struct DoUndoLocals {
        bool shouldTestLiquidity;
        bool shouldTestSwapAmount;
        bool shouldTestFee;
        uint256 liquidityWaDai;
        uint256 liquidityWaWeth;
        uint256 poolSwapFeePercentage;
    }

    function _testDoUndoExactInBase(uint256 exactDaiAmountIn, DoUndoLocals memory testLocals) private {
        if (testLocals.shouldTestLiquidity) {
            _setPoolBalances(testLocals.liquidityWaDai, testLocals.liquidityWaWeth);
        }

        maxSwapAmount = _getMaxSwapAmount();

        if (testLocals.shouldTestSwapAmount) {
            exactDaiAmountIn = bound(exactDaiAmountIn, minSwapAmount, maxSwapAmount);
        } else {
            exactDaiAmountIn = maxSwapAmount;
        }

        if (testLocals.shouldTestFee) {
            testLocals.poolSwapFeePercentage = bound(
                testLocals.poolSwapFeePercentage,
                minPoolSwapFeePercentage,
                maxPoolSwapFeePercentage
            );
        } else {
            testLocals.poolSwapFeePercentage = minPoolSwapFeePercentage;
        }

        vault.manualSetStaticSwapFeePercentage(pool, testLocals.poolSwapFeePercentage);

        vm.assertEq(
            vault.getAggregateSwapFeeAmount(pool, IERC20(address(waDAI))),
            0,
            "Collected fees for waDAI are wrong"
        );
        vm.assertEq(
            vault.getAggregateSwapFeeAmount(pool, IERC20(address(waWETH))),
            0,
            "Collected fees for waWETH are wrong"
        );

        TestBalances memory balancesBefore = _getTestBalances(bob);

        IBatchRouter.SwapPathExactAmountIn[] memory pathsDo = _buildExactInPaths(dai, exactDaiAmountIn);
        vm.prank(bob);
        (uint256[] memory pathAmountsOut, , ) = batchRouter.swapExactIn(pathsDo, MAX_UINT256, false, bytes(""));

        // If amountsOut is smaller than minSwapAmount, we won't be able to undo the operation, so ignore the test.
        vm.assume(pathAmountsOut[0] > minSwapAmount);

        // If we insert only pathAmountsOut, the user WETH balance will go back to where it was before and we won't be
        // able to measure fees. So, we make the user pay the exact WETH fees back. Then, when we compare the DAI
        // balance, we can make sure that it's not paying fees twice.
        IBatchRouter.SwapPathExactAmountIn[] memory pathsUndo = _buildExactInPaths(weth, pathAmountsOut[0]);
        vm.prank(bob);
        batchRouter.swapExactIn(pathsUndo, MAX_UINT256, false, bytes(""));

        TestBalances memory balancesAfter = _getTestBalances(bob);

        _checkUserBalancesAndPoolInvariant(balancesBefore, balancesAfter);
    }

    function _testDoUndoExactOutBase(uint256 exactWethAmountOut, DoUndoLocals memory testLocals) private {
        if (testLocals.shouldTestLiquidity) {
            _setPoolBalances(testLocals.liquidityWaDai, testLocals.liquidityWaWeth);
        }

        maxSwapAmount = _getMaxSwapAmount();

        if (testLocals.shouldTestSwapAmount) {
            exactWethAmountOut = bound(exactWethAmountOut, minSwapAmount, maxSwapAmount);
        } else {
            exactWethAmountOut = maxSwapAmount;
        }

        if (testLocals.shouldTestFee) {
            testLocals.poolSwapFeePercentage = bound(
                testLocals.poolSwapFeePercentage,
                minPoolSwapFeePercentage,
                maxPoolSwapFeePercentage
            );
        } else {
            testLocals.poolSwapFeePercentage = minPoolSwapFeePercentage;
        }

        vault.manualSetStaticSwapFeePercentage(pool, testLocals.poolSwapFeePercentage);

        vm.assertEq(
            vault.getAggregateSwapFeeAmount(pool, IERC20(address(waDAI))),
            0,
            "Collected fees for waDAI are wrong"
        );
        vm.assertEq(
            vault.getAggregateSwapFeeAmount(pool, IERC20(address(waWETH))),
            0,
            "Collected fees for waWETH are wrong"
        );

        TestBalances memory balancesBefore = _getTestBalances(bob);

        IBatchRouter.SwapPathExactAmountOut[] memory pathsDo = _buildExactOutPaths(weth, exactWethAmountOut);
        vm.prank(bob);
        (uint256[] memory pathAmountsIn, , ) = batchRouter.swapExactOut(pathsDo, MAX_UINT256, false, bytes(""));

        // If amountsIn is smaller than minSwapAmount, we won't be able to undo the operation, so ignore the test.
        vm.assume(pathAmountsIn[0] > minSwapAmount);

        // If we use only pathAmountsIn, the user DAI balance will go back to where it was before and we won't be
        // able to measure fees. So, we make the user discount the exact DAI fees. Then, when we compare the WETH
        // balance, we can make sure that it's not paying fees twice.
        IBatchRouter.SwapPathExactAmountOut[] memory pathsUndo = _buildExactOutPaths(dai, pathAmountsIn[0]);
        vm.prank(bob);
        batchRouter.swapExactOut(pathsUndo, MAX_UINT256, false, bytes(""));

        TestBalances memory balancesAfter = _getTestBalances(bob);

        _checkUserBalancesAndPoolInvariant(balancesBefore, balancesAfter);
    }

    function _checkUserBalancesAndPoolInvariant(
        TestBalances memory balancesBefore,
        TestBalances memory balancesAfter
    ) private view {
        // Pool invariant should never decrease.
        assertGe(
            balancesAfter.balances.poolInvariant,
            balancesBefore.balances.poolInvariant,
            "Pool invariant decreased"
        );

        // User balances should be smaller than before, and user should pay the fees.
        assertLe(
            balancesAfter.balances.bobTokens[balancesAfter.daiIdx],
            balancesBefore.balances.bobTokens[balancesBefore.daiIdx],
            "Sender DAI balance is incorrect"
        );
        assertLe(
            balancesAfter.balances.bobTokens[balancesAfter.wethIdx],
            balancesBefore.balances.bobTokens[balancesBefore.wethIdx],
            "Sender WETH balance is incorrect"
        );

        // All tokens paid by the user should stay in the Vault since pool creator fees were not charged yet. However,
        // calculating the amount of tokens in the Vault involves previewRedeem, used multiple times by buffers,
        // fee calculation, and to transform wrapped amounts in underlying amounts, which introduces rounding errors to
        // compare user and vault amounts. Make sure this rounding error is below 10 wei.
        uint256 senderDaiDelta = balancesBefore.balances.bobTokens[balancesBefore.daiIdx] -
            balancesAfter.balances.bobTokens[balancesAfter.daiIdx];
        uint256 vaultTotalDaiBefore = balancesBefore.balances.vaultTokens[balancesBefore.daiIdx] +
            waDAI.previewRedeem(balancesBefore.balances.vaultTokens[balancesBefore.waDaiIdx]);
        uint256 vaultTotalDaiAfter = balancesAfter.balances.vaultTokens[balancesAfter.daiIdx] +
            waDAI.previewRedeem(balancesAfter.balances.vaultTokens[balancesAfter.waDaiIdx]);

        // `vaultTotalDaiAfter - vaultTotalDaiBefore = senderDaiDelta`, solve for daiAfter to prevent underflow.
        assertApproxEqAbs(
            vaultTotalDaiAfter,
            senderDaiDelta + vaultTotalDaiBefore,
            MAX_ERROR,
            "Vault dai/waDAI balance is wrong"
        );

        // All tokens paid by the user should stay in the Vault since pool creator fees were not charged yet. However,
        // calculating the amount of tokens in the Vault involves previewRedeem, used multiple times by buffers,
        // fee calculation, and to transform wrapped amounts in underlying amounts, which introduces rounding errors to
        // compare user and vault amounts. Make sure this rounding error is below 10 wei.
        uint256 senderWethDelta = balancesBefore.balances.bobTokens[balancesBefore.wethIdx] -
            balancesAfter.balances.bobTokens[balancesAfter.wethIdx];
        uint256 vaultTotalWethBefore = balancesBefore.balances.vaultTokens[balancesBefore.wethIdx] +
            waWETH.previewRedeem(balancesBefore.balances.vaultTokens[balancesBefore.waWethIdx]);
        uint256 vaultTotalWethAfter = balancesAfter.balances.vaultTokens[balancesAfter.wethIdx] +
            waWETH.previewRedeem(balancesAfter.balances.vaultTokens[balancesAfter.waWethIdx]);

        // `vaultTotalWethAfter - vaultTotalWethBefore = senderWethDelta`, solve for wethAfter to prevent underflow.
        assertApproxEqAbs(
            vaultTotalWethAfter,
            senderWethDelta + vaultTotalWethBefore,
            MAX_ERROR,
            "Vault weth/waWETH balance is wrong"
        );

        // This can only happen in WETH, since the caller puts back in the undo operation all the WETH tokens that Do
        // operation retrieved for him. The WETH balance of the user is effectively 0, so the vault should have the
        // same balance. However, due to changes in the rate of the wrapped tokens, an error may occur and we detect
        // that the vault lost part of the WETH tokens, but that's just a conversion rounding issue if the rate has
        // changed.
        if (vaultTotalWethBefore > vaultTotalWethAfter) {
            // If vault lost some WETH value in WETH and waWETH tokens, it may be due to the token rate that changed
            // after the buffer operations, so the vault has the same value but converted differently.
            assertGt(
                balancesAfter.waWETHRate,
                balancesBefore.waWETHRate,
                "waWETH rate did not increase with Do/Undo operation"
            );
        }

        // DAI and WETH are worth the same. So, we can sum the deltas for DAI and WETH in the vault, and compare with
        // how much the user paid in fees. The user cannot have any benefit, but the vault and the user amount may
        // differ because of rounding. Let's call the sum of vault deltas as sumDeltaVault, and the sum of sender
        // deltas as sumDeltaSender, the test belows tests if
        // `sumDeltaSender - 2 * MAX_ERROR < sumDeltaVault < sumDeltaSender`, it means, vault delta is smaller than
        // sender delta (sender paid more than vault received), but the difference is small.
        uint256 sumDeltaVault = vaultTotalWethAfter + vaultTotalDaiAfter - vaultTotalDaiBefore - vaultTotalWethBefore;
        uint256 sumDeltaSender = senderWethDelta + senderDaiDelta;
        assertApproxEqAbs(
            sumDeltaVault,
            sumDeltaSender,
            MAX_ERROR,
            "Sum of tokens in the vault after Do/Undo operation is wrong"
        );
        assertLe(sumDeltaVault, sumDeltaSender, "Sender paid less tokens than vault delta");
    }

    function _buildExactInPaths(
        IERC20 tokenIn,
        uint256 amountIn
    ) private view returns (IBatchRouter.SwapPathExactAmountIn[] memory paths) {
        IBatchRouter.SwapPathStep[] memory steps = new IBatchRouter.SwapPathStep[](3);
        paths = new IBatchRouter.SwapPathExactAmountIn[](1);

        // Since this is exact in, swaps will be executed in the order given.
        // Pre-swap through DAI buffer to get waDAI, then main swap waDAI for waWETH in the yield-bearing pool,
        // and finally post-swap the waWETH through the WETH buffer to calculate the WETH amount out.
        // The only token transfers are DAI in (given) and WETH out (calculated).
        if (tokenIn == dai) {
            steps[0] = IBatchRouter.SwapPathStep({ pool: address(waDAI), tokenOut: waDAI, isBuffer: true });
            steps[1] = IBatchRouter.SwapPathStep({ pool: erc4626Pool, tokenOut: waWETH, isBuffer: false });
            steps[2] = IBatchRouter.SwapPathStep({ pool: address(waWETH), tokenOut: weth, isBuffer: true });
        } else {
            steps[0] = IBatchRouter.SwapPathStep({ pool: address(waWETH), tokenOut: waWETH, isBuffer: true });
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
        IERC20 tokenIn = tokenOut == dai ? IERC20(address(weth)) : dai;

        // Since this is exact out, swaps will be executed in reverse order (though we submit in logical order).
        // Pre-swap through the WETH buffer to get waWETH, then main swap waWETH for waDAI in the yield-bearing pool,
        // and finally post-swap the waDAI for DAI through the DAI buffer to calculate the DAI amount in.
        // The only token transfers are DAI in (calculated) and WETH out (given).
        if (tokenIn == dai) {
            steps[0] = IBatchRouter.SwapPathStep({ pool: address(waDAI), tokenOut: waDAI, isBuffer: true });
            steps[1] = IBatchRouter.SwapPathStep({ pool: erc4626Pool, tokenOut: waWETH, isBuffer: false });
            steps[2] = IBatchRouter.SwapPathStep({ pool: address(waWETH), tokenOut: weth, isBuffer: true });
        } else {
            steps[0] = IBatchRouter.SwapPathStep({ pool: address(waWETH), tokenOut: waWETH, isBuffer: true });
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

    function _setPoolBalances(uint256 liquidityWaDai, uint256 liquidityWaWeth) private {
        // 1% to 10000% of erc4626 initial pool liquidity.
        liquidityWaDai = bound(
            liquidityWaDai,
            erc4626PoolInitialAmount.mulDown(1e16),
            erc4626PoolInitialAmount.mulDown(10000e16)
        );
        liquidityWaDai = waDAI.previewDeposit(liquidityWaDai);
        // 1% to 10000% of erc4626 initial pool liquidity.
        liquidityWaWeth = bound(
            liquidityWaWeth,
            erc4626PoolInitialAmount.mulDown(1e16),
            erc4626PoolInitialAmount.mulDown(10000e16)
        );
        liquidityWaWeth = waWETH.previewDeposit(liquidityWaWeth);

        uint256[] memory newPoolBalance = new uint256[](2);
        newPoolBalance[waDaiIdx] = liquidityWaDai;
        newPoolBalance[waWethIdx] = liquidityWaWeth;

        uint256[] memory newPoolBalanceLiveScaled18 = new uint256[](2);
        newPoolBalanceLiveScaled18[waDaiIdx] = liquidityWaDai.toScaled18ApplyRateRoundUp(1, waDAI.getRate());
        newPoolBalanceLiveScaled18[waWethIdx] = liquidityWaWeth.toScaled18ApplyRateRoundUp(1, waWETH.getRate());

        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(pool);
        vault.manualSetPoolTokensAndBalances(pool, tokens, newPoolBalance, newPoolBalanceLiveScaled18);
        // Updates pool data with latest token rates.
        vault.loadPoolDataUpdatingBalancesAndYieldFees(pool, Rounding.ROUND_DOWN);
    }

    function _getMaxSwapAmount() private view returns (uint256 newMaxSwapAmount) {
        // In the case of an yield-bearing pool, lastBalancesLiveScaled18 is the same as the balances in underlying
        // terms, if underlying and wrapped tokens have 18 decimals.
        (, , , uint256[] memory underlyingBalances) = vault.getPoolTokenInfo(pool);
        uint256 smallerBalance = underlyingBalances[waDaiIdx] < underlyingBalances[waWethIdx]
            ? underlyingBalances[waDaiIdx]
            : underlyingBalances[waWethIdx];
        return smallerBalance.mulDown(25e16); // 25% of the smallest pool liquidity.
    }

    struct BufferBalances {
        uint256 underlying;
        uint256 wrapped;
    }

    struct TestBalances {
        BaseVaultTest.Balances balances;
        BufferBalances waWETHBuffer;
        BufferBalances waDAIBuffer;
        uint256 waDAIRate;
        uint256 waWETHRate;
        uint256 daiIdx;
        uint256 wethIdx;
        uint256 waDaiIdx;
        uint256 waWethIdx;
    }

    function _getTestBalances(address sender) private view returns (TestBalances memory testBalances) {
        // The index of each token is defined by the order of tokenArray, defined right below.
        testBalances.daiIdx = 0;
        testBalances.wethIdx = 1;
        testBalances.waDaiIdx = 2;
        testBalances.waWethIdx = 3;
        IERC20[] memory tokenArray = [address(dai), address(weth), address(waDAI), address(waWETH)]
            .toMemoryArray()
            .asIERC20();
        testBalances.balances = getBalances(sender, tokenArray);

        (uint256 waDAIBufferBalanceUnderlying, uint256 waDAIBufferBalanceWrapped) = vault.getBufferBalance(waDAI);
        testBalances.waDAIBuffer.underlying = waDAIBufferBalanceUnderlying;
        testBalances.waDAIBuffer.wrapped = waDAIBufferBalanceWrapped;

        (uint256 waWETHBufferBalanceUnderlying, uint256 waWETHBufferBalanceWrapped) = vault.getBufferBalance(waWETH);
        testBalances.waWETHBuffer.underlying = waWETHBufferBalanceUnderlying;
        testBalances.waWETHBuffer.wrapped = waWETHBufferBalanceWrapped;

        // The rate only affects swaps of a very large amount (over 1e28), so we get the rate with this amount of
        // precision.
        testBalances.waDAIRate = waDAI.previewRedeem(1e10 * FixedPoint.ONE);
        testBalances.waWETHRate = waWETH.previewRedeem(1e10 * FixedPoint.ONE);
    }

    function _donateToVault() internal virtual {
        vm.startPrank(address(vault));

        uint256 underlyingToDeposit = 10000 * erc4626PoolInitialAmount;
        dai.mint(address(vault), underlyingToDeposit);
        vm.deal(payable(address(vault)), address(vault).balance + underlyingToDeposit);
        weth.deposit{ value: underlyingToDeposit }();

        dai.approve(address(waDAI), underlyingToDeposit);
        uint256 mintedWaDAI = waDAI.deposit(underlyingToDeposit, address(vault));

        weth.approve(address(waWETH), underlyingToDeposit);
        uint256 mintedWaWETH = waWETH.deposit(underlyingToDeposit, address(vault));
        vm.stopPrank();

        // Override vault liquidity, to make sure the extra liquidity is registered.
        vault.manualSetReservesOf(IERC20(address(waDAI)), mintedWaDAI);
        vault.manualSetReservesOf(IERC20(address(waWETH)), mintedWaWETH);
    }
}
