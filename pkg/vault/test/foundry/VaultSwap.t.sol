// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IVaultEvents } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultEvents.sol";
import { IProtocolFeeController } from "@balancer-labs/v3-interfaces/contracts/vault/IProtocolFeeController.sol";
import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";

import {
    SwapKind,
    SwapParams,
    HooksConfig,
    PoolSwapParams
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { PoolMock } from "../../contracts/test/PoolMock.sol";
import { PoolHooksMock } from "../../contracts/test/PoolHooksMock.sol";
import { RouterCommon } from "../../contracts/RouterCommon.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract VaultSwapTest is BaseVaultTest {
    using FixedPoint for uint256;

    PoolMock internal noInitPool;
    uint256 internal swapFeeExactIn = defaultAmount / 100; // 1%
    uint256 internal swapFeeExactOut = defaultAmount.mulDivUp(1e16, uint256(1e16).complement()); // 1%/(100% - 1%)
    uint256 internal protocolSwapFeeExactIn = swapFeeExactIn / 2; // 50%
    uint256 internal protocolSwapFeeExactOut = swapFeeExactOut.divUp(2e18); // 50%

    // Track the indices for the standard dai/usdc pool.
    uint256 internal daiIdx;
    uint256 internal usdcIdx;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        noInitPool = PoolMock(createPool());

        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));
    }

    /// Swap

    function testCannotSwapWhenPaused() public {
        vault.manualPausePool(pool);

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.PoolPaused.selector, pool));

        vm.prank(bob);
        router.swapSingleTokenExactIn(pool, usdc, dai, defaultAmount, defaultAmount, MAX_UINT256, false, bytes(""));
    }

    function testSwapNotInitialized() public {
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.PoolNotInitialized.selector, address(noInitPool)));
        router.swapSingleTokenExactIn(
            address(noInitPool),
            usdc,
            dai,
            defaultAmount,
            defaultAmount,
            MAX_UINT256,
            false,
            bytes("")
        );
    }

    function testSwapSymmetry() public {
        setSwapFeePercentage(swapFeePercentage);

        uint256 snapshotId = vm.snapshot();

        vm.prank(alice);
        uint256 amountOut = router.swapSingleTokenExactIn(
            pool,
            usdc,
            dai,
            defaultAmount,
            0,
            MAX_UINT256,
            false,
            bytes("")
        );

        vm.revertTo(snapshotId);

        vm.prank(alice);
        uint256 amountIn = router.swapSingleTokenExactOut(
            pool,
            usdc,
            dai,
            amountOut,
            MAX_UINT128,
            MAX_UINT256,
            false,
            bytes("")
        );

        // An ExactIn swap with `defaultAmount` tokenIn returned `amountOut` tokenOut.
        // Since Exact_In and Exact_Out are symmetrical, an ExactOut swap with `amountOut` tokenOut should return the
        // same amount of tokenIn.
        assertEq(amountIn, defaultAmount, "Swap fees are not symmetric for ExactIn and ExactOut");
    }

    function testSwapLimitExactIn() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.SwapLimit.selector, defaultAmount - 1, defaultAmount));
        router.swapSingleTokenExactIn(pool, usdc, dai, defaultAmount - 1, defaultAmount, MAX_UINT256, false, bytes(""));
    }

    function testSwapTooSmallAmountGiven() public {
        vm.prank(alice);
        vm.expectRevert(IVaultErrors.TradeAmountTooSmall.selector);
        router.swapSingleTokenExactIn(pool, usdc, dai, MIN_TRADE_AMOUNT - 1, 0, MAX_UINT256, false, bytes(""));
    }

    function testSwapDeadlineExactIn() public {
        vm.prank(alice);
        vm.expectRevert(RouterCommon.SwapDeadline.selector);
        router.swapSingleTokenExactIn(
            pool,
            usdc,
            dai,
            defaultAmount,
            defaultAmount,
            block.timestamp - 1,
            false,
            bytes("")
        );
    }

    function testSwapLimitExactOut() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.SwapLimit.selector, defaultAmount, defaultAmount - 1));
        router.swapSingleTokenExactOut(
            pool,
            usdc,
            dai,
            defaultAmount,
            defaultAmount - 1,
            MAX_UINT256,
            false,
            bytes("")
        );
    }

    function testSwapDeadlineExactOut() public {
        vm.prank(alice);
        vm.expectRevert(RouterCommon.SwapDeadline.selector);
        router.swapSingleTokenExactOut(
            pool,
            usdc,
            dai,
            defaultAmount,
            defaultAmount,
            block.timestamp - 1,
            false,
            bytes("")
        );
    }

    function testSwapSingleTokenExactIn() public {
        assertSwap(swapSingleTokenExactIn, SwapKind.EXACT_IN);
    }

    function testSwapSingleTokenExactInWithDust() public {
        dai.mint(address(vault), 1);
        usdc.mint(address(vault), 1);
        assertSwap(swapSingleTokenExactIn, SwapKind.EXACT_IN);
    }

    function swapSingleTokenExactIn() public returns (uint256 fee, uint256 protocolFee) {
        vm.prank(alice);
        router.swapSingleTokenExactIn(pool, usdc, dai, defaultAmount, defaultAmount, MAX_UINT256, false, bytes(""));
        return (0, 0);
    }

    function testSwapSingleTokenExactOut() public {
        assertSwap(swapSingleTokenExactOut, SwapKind.EXACT_OUT);
    }

    function testSwapSingleTokenExactOutWithDust() public {
        dai.mint(address(vault), 1);
        usdc.mint(address(vault), 1);
        assertSwap(swapSingleTokenExactOut, SwapKind.EXACT_OUT);
    }

    function swapSingleTokenExactOut() public returns (uint256 fee, uint256 protocolFee) {
        vm.prank(alice);
        router.swapSingleTokenExactOut(pool, usdc, dai, defaultAmount, defaultAmount, MAX_UINT256, false, bytes(""));
        return (0, 0);
    }

    function testSwapSingleTokenExactInWithFee() public {
        assertSwap(swapSingleTokenExactInWithFee, SwapKind.EXACT_IN);
    }

    function testSwapEventExactIn() public {
        setSwapFeePercentage(swapFeePercentage);

        vm.expectEmit();
        emit IVaultEvents.Swap(
            pool,
            usdc,
            dai,
            defaultAmount,
            defaultAmount - swapFeeExactIn,
            swapFeePercentage,
            defaultAmount.mulDown(swapFeePercentage),
            dai
        );

        vm.prank(alice);
        router.swapSingleTokenExactIn(
            pool,
            usdc,
            dai,
            defaultAmount,
            defaultAmount - swapFeeExactIn,
            MAX_UINT256,
            false,
            bytes("")
        );
    }

    function testSwapEventExactOut() public {
        setSwapFeePercentage(swapFeePercentage);

        vm.expectEmit();
        emit IVaultEvents.Swap(
            pool,
            usdc,
            dai,
            defaultAmount + swapFeeExactOut,
            defaultAmount,
            swapFeePercentage,
            swapFeeExactOut,
            usdc
        );

        vm.prank(alice);
        router.swapSingleTokenExactOut(
            pool,
            usdc,
            dai,
            defaultAmount,
            defaultAmount + swapFeeExactOut,
            MAX_UINT256,
            false,
            bytes("")
        );
    }

    function swapSingleTokenExactInWithFee() public returns (uint256 fee, uint256 protocolFee) {
        setSwapFeePercentage(swapFeePercentage);

        vm.prank(alice);
        router.swapSingleTokenExactIn(
            pool,
            usdc,
            dai,
            defaultAmount,
            defaultAmount - swapFeeExactIn,
            MAX_UINT256,
            false,
            bytes("")
        );

        return (swapFeeExactIn, 0);
    }

    function testSwapSingleTokenExactInWithProtocolFee() public {
        assertSwap(swapSingleTokenExactInWithProtocolFee, SwapKind.EXACT_IN);
    }

    function testSwapSingleTokenExactInWithFeeInRecoveryMode() public {
        // Put pool in recovery mode.
        vault.manualEnableRecoveryMode(pool);

        assertSwap(swapSingleTokenExactInWithFeeInRecoveryMode, SwapKind.EXACT_IN);
    }

    function swapSingleTokenExactInWithFeeInRecoveryMode() public returns (uint256 fee, uint256 protocolFee) {
        // Call regular function (which sets the protocol swap fee), but return a fee of 0 to the validation function.
        protocolFee = 0;
        (fee, ) = swapSingleTokenExactInWithProtocolFee();
    }

    function swapSingleTokenExactInWithProtocolFee() public returns (uint256 fee, uint256 protocolFee) {
        setSwapFeePercentage(swapFeePercentage);
        vault.manualSetAggregateSwapFeePercentage(pool, protocolSwapFeePercentage);

        vm.prank(alice);
        router.swapSingleTokenExactIn(
            pool,
            usdc,
            dai,
            defaultAmount,
            defaultAmount - swapFeeExactIn,
            MAX_UINT256,
            false,
            bytes("")
        );

        return (swapFeeExactIn, protocolSwapFeeExactIn);
    }

    function testSwapSingleTokenExactOutWithFee() public {
        assertSwap(swapSingleTokenExactOutWithFee, SwapKind.EXACT_OUT);
    }

    function swapSingleTokenExactOutWithFee() public returns (uint256 fee, uint256 protocolFee) {
        setSwapFeePercentage(swapFeePercentage);

        vm.prank(alice);
        router.swapSingleTokenExactOut(
            pool,
            usdc, // tokenIn
            dai, // tokenOut
            defaultAmount, // exactAmountOut
            defaultAmount + swapFeeExactOut, // maxAmountIn
            MAX_UINT256,
            false,
            bytes("")
        );

        return (swapFeeExactOut, 0);
    }

    function testSwapSingleTokenExactOutWithProtocolFee() public {
        assertSwap(swapSingleTokenExactOutWithProtocolFee, SwapKind.EXACT_OUT);
    }

    function testSwapSingleTokenExactOutWithFeeInRecoveryMode() public {
        // Put pool in recovery mode.
        vault.manualEnableRecoveryMode(pool);

        assertSwap(swapSingleTokenExactOutWithFeeInRecoveryMode, SwapKind.EXACT_OUT);
    }

    function swapSingleTokenExactOutWithFeeInRecoveryMode() public returns (uint256 fee, uint256 protocolFee) {
        setSwapFeePercentage(swapFeePercentage);

        // Call regular function (which sets the protocol swap fee), but return a fee of 0 to the validation function.
        protocolFee = 0;
        (fee, ) = swapSingleTokenExactOutWithProtocolFee();
    }

    function swapSingleTokenExactOutWithProtocolFee() public returns (uint256 fee, uint256 protocolFee) {
        setSwapFeePercentage(swapFeePercentage);
        vault.manualSetAggregateSwapFeePercentage(pool, protocolSwapFeePercentage);

        vm.prank(alice);
        router.swapSingleTokenExactOut(
            pool,
            usdc, // tokenIn
            dai, // tokenOut
            defaultAmount, // exactAmountOut
            defaultAmount + swapFeeExactOut, // maxAmountIn
            MAX_UINT256,
            false,
            bytes("")
        );

        return (swapFeeExactOut, protocolSwapFeeExactOut);
    }

    function testProtocolSwapFeeAccumulation() public {
        assertSwap(protocolSwapFeeAccumulation, SwapKind.EXACT_IN);
    }

    function protocolSwapFeeAccumulation() public returns (uint256 fee, uint256 protocolFee) {
        setSwapFeePercentage(swapFeePercentage);
        vault.manualSetAggregateSwapFeePercentage(pool, protocolSwapFeePercentage);

        vm.prank(alice);
        router.swapSingleTokenExactIn(
            pool,
            usdc,
            dai,
            defaultAmount / 2,
            defaultAmount / 2 - swapFeeExactIn / 2,
            MAX_UINT256,
            false,
            bytes("")
        );

        vm.prank(alice);
        router.swapSingleTokenExactIn(
            pool,
            usdc,
            dai,
            defaultAmount / 2,
            defaultAmount / 2 - swapFeeExactIn / 2,
            MAX_UINT256,
            false,
            bytes("")
        );

        return (swapFeeExactIn, protocolSwapFeeExactIn);
    }

    function testCollectAggregateFees() public {
        usdc.mint(bob, defaultAmount);

        setSwapFeePercentage(swapFeePercentage);
        vault.manualSetAggregateSwapFeePercentage(pool, protocolSwapFeePercentage);

        vm.prank(bob);
        router.swapSingleTokenExactIn(
            pool,
            usdc,
            dai,
            defaultAmount,
            defaultAmount - swapFeeExactIn,
            MAX_UINT256,
            false,
            bytes("")
        );

        IProtocolFeeController feeController = vault.getProtocolFeeController();
        vault.collectAggregateFees(pool);
        uint256[] memory feeAmounts = feeController.getProtocolFeeAmounts(pool);

        authorizer.grantRole(
            IAuthentication(address(feeController)).getActionId(IProtocolFeeController.withdrawProtocolFees.selector),
            admin
        );
        vm.prank(admin);
        feeController.withdrawProtocolFees(pool, admin);

        // Protocol fees are zero.
        assertEq(0, feeAmounts[usdcIdx], "Protocol fees are not zero");

        // Alice received protocol fees.
        assertEq(dai.balanceOf(admin) - defaultBalance, protocolSwapFeeExactIn, "Protocol fees not collected");
    }

    function reentrancyHook() public {
        // Do second swap.
        SwapParams memory params = SwapParams({
            kind: SwapKind.EXACT_IN,
            pool: pool,
            tokenIn: dai,
            tokenOut: usdc,
            amountGivenRaw: defaultAmount,
            limitRaw: 0,
            userData: bytes("")
        });
        vault.swap(params);
    }

    function startSwap() public {
        SwapParams memory params = SwapParams({
            kind: SwapKind.EXACT_IN,
            pool: pool,
            tokenIn: usdc,
            tokenOut: dai,
            amountGivenRaw: defaultAmount,
            limitRaw: 0,
            userData: bytes("")
        });
        vault.swap(params);
    }

    function testReentrancySwap() public {
        // Enable before swap.
        HooksConfig memory config = vault.getHooksConfig(pool);
        config.shouldCallBeforeSwap = true;
        vault.manualSetHooksConfig(pool, config);

        // Enable reentrancy hook.
        PoolHooksMock(poolHooksContract).setSwapReentrancyHookActive(true);
        PoolHooksMock(poolHooksContract).setSwapReentrancyHook(
            address(this),
            abi.encodeWithSelector(this.reentrancyHook.selector)
        );

        // Disable storing router's sender (This test is used as router but does not implement getSender).
        PoolHooksMock(poolHooksContract).setShouldIgnoreSavedSender(true);

        uint256 usdcBeforeSwap = usdc.balanceOf(address(this));
        uint256 daiBeforeSwap = dai.balanceOf(address(this));

        (, , uint256[] memory balancesRawBefore, ) = vault.getPoolTokenInfo(pool);

        vault.unlock(abi.encode(this.startSwap.selector));

        (, , uint256[] memory balancesRawAfter, ) = vault.getPoolTokenInfo(pool);

        // Pool balances should not change.
        for (uint256 i = 0; i < balancesRawAfter.length; ++i) {
            assertEq(balancesRawBefore[i], balancesRawAfter[i], "Balance does not match");
        }
        // No tokens being spent.
        assertEq(usdcBeforeSwap, usdc.balanceOf(address(this)), "USDC balance changed");
        assertEq(daiBeforeSwap, dai.balanceOf(address(this)), "DAI balance changed");
    }

    /// Utils

    struct SwapBalances {
        uint256 vaultDai;
        uint256 vaultUsdc;
        uint256 userDai;
        uint256 userUsdc;
    }

    function assertSwap(function() returns (uint256, uint256) testFunc, SwapKind kind) internal {
        SwapBalances memory balancesBefore;
        balancesBefore.vaultUsdc = usdc.balanceOf(address(vault));
        balancesBefore.vaultDai = dai.balanceOf(address(vault));

        balancesBefore.userUsdc = usdc.balanceOf(alice);
        balancesBefore.userDai = dai.balanceOf(alice);

        uint256 daiFee;
        uint256 usdcFee;
        uint256 daiProtocolFee;
        uint256 usdcProtocolFee;

        (uint256 fee, uint256 protocolFee) = testFunc();

        if (kind == SwapKind.EXACT_OUT) {
            usdcFee = fee;
            usdcProtocolFee = protocolFee;
        } else {
            daiFee = fee;
            daiProtocolFee = protocolFee;
        }

        // assets are transferred to/from user.
        assertEq(
            usdc.balanceOf(alice),
            balancesBefore.userUsdc - defaultAmount - usdcFee,
            "Swap: User's USDC balance is wrong"
        );
        assertEq(
            dai.balanceOf(alice),
            balancesBefore.userDai + defaultAmount - daiFee,
            "Swap: User's DAI balance is wrong"
        );

        // Tokens are adjusted in the pool.
        (, , uint256[] memory balances, ) = vault.getPoolTokenInfo(pool);
        assertEq(balances[daiIdx], daiFee - daiProtocolFee, "Swap: Pool's [0] balance is wrong");
        assertEq(balances[usdcIdx], 2 * defaultAmount + usdcFee - usdcProtocolFee, "Swap: Pool's [1] balance is wrong");

        // Protocol fees are accrued.
        uint256 actualFee = vault.manualGetAggregateSwapFeeAmount(pool, kind == SwapKind.EXACT_OUT ? usdc : dai);
        assertEq(protocolFee, actualFee, "Swap: Aggregate fee amount is wrong");

        // Vault has adjusted balances.
        assertEq(
            balancesBefore.vaultDai - dai.balanceOf(address(vault)),
            defaultAmount - daiFee,
            "Swap: Vault's DAI balance is wrong"
        );
        assertEq(
            usdc.balanceOf(address(vault)) - balancesBefore.vaultUsdc,
            defaultAmount + usdcFee,
            "Swap: Vault's USDC balance is wrong"
        );

        // Ensure raw and last live balances are in sync after the operation.
        uint256[] memory currentLiveBalances = vault.getCurrentLiveBalances(pool);
        uint256[] memory lastBalancesLiveScaled18 = vault.getLastLiveBalances(pool);

        assertEq(currentLiveBalances.length, lastBalancesLiveScaled18.length);

        for (uint256 i = 0; i < currentLiveBalances.length; ++i) {
            assertEq(currentLiveBalances[i], lastBalancesLiveScaled18[i]);
        }
    }
}
