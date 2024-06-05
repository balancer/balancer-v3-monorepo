// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";

import { BalancerPoolToken } from "../../contracts/BalancerPoolToken.sol";
import { PoolHooksMock } from "../../contracts/test/PoolHooksMock.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract HooksAddLiquidityFeesAndDiscountsTest is BaseVaultTest {
    using ArrayHelpers for *;

    uint256 internal daiIdx;
    uint256 internal usdcIdx;

    uint256 private _swapAmount;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        _swapAmount = poolInitAmount / 100;

        // Sets the pool address in the hook, so we can check balances of the pool inside the hook
        PoolHooksMock(poolHooksContract).setPool(address(pool));

        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));
    }

    function testOnBeforeAddLiquidityHookFeeExactIn() public {
        HooksConfig memory hooksConfig = vault.getHooksConfig(address(pool));
        hooksConfig.shouldCallBeforeAddLiquidity = true;
        vault.setHooksConfig(address(pool), hooksConfig);

        uint256[] memory originalBalances = [poolInitAmount, poolInitAmount].toMemoryArray();
        uint256[] memory expectedAmountsIn = [_swapAmount, _swapAmount].toMemoryArray();

        uint256 hookFee = 1e3;
        PoolHooksMock(poolHooksContract).setOnBeforeAddLiquidityHookFee(hookFee);

        HookTestLocals memory testLocals = _createHookTestLocals();

        // Check that the swap gets updated balances that reflect the updated balance in the before hook
        vm.prank(bob);
        // Check if balances were not changed before onBeforeHook
        vm.expectCall(
            address(poolHooksContract),
            abi.encodeWithSelector(
                IHooks.onBeforeAddLiquidity.selector,
                address(router),
                pool,
                AddLiquidityKind.UNBALANCED,
                expectedAmountsIn,
                expectedAmountsIn,
                _swapAmount,
                originalBalances,
                bytes("")
            )
        );

        router.addLiquidityUnbalanced(pool, expectedAmountsIn, _swapAmount, false, bytes(""));

        uint256 expectedBptOut = 0;
        for (uint256 i = 0; i < expectedAmountsIn.length; i++) {
            expectedBptOut += (expectedAmountsIn[i] - hookFee);
        }

        _checkAddLiquidityHookTestResults(testLocals, expectedAmountsIn, expectedBptOut, hookFee, 0);
    }

    function testOnBeforeAddLiquidityHookDiscountExactIn() public {
        HooksConfig memory hooksConfig = vault.getHooksConfig(address(pool));
        hooksConfig.shouldCallBeforeAddLiquidity = true;
        vault.setHooksConfig(address(pool), hooksConfig);

        uint256[] memory originalBalances = [poolInitAmount, poolInitAmount].toMemoryArray();
        uint256[] memory expectedAmountsIn = [_swapAmount, _swapAmount].toMemoryArray();

        uint256 hookDiscount = 1e3;
        PoolHooksMock(poolHooksContract).setOnBeforeAddLiquidityHookDiscount(hookDiscount);

        // Mint tokens so that hook can pay for the discount
        dai.mint(poolHooksContract, hookDiscount);
        usdc.mint(poolHooksContract, hookDiscount);

        HookTestLocals memory testLocals = _createHookTestLocals();

        // Check that the swap gets updated balances that reflect the updated balance in the before hook
        vm.prank(bob);
        // Check if balances were not changed before onBeforeHook
        vm.expectCall(
            address(poolHooksContract),
            abi.encodeWithSelector(
                IHooks.onBeforeAddLiquidity.selector,
                address(router),
                pool,
                AddLiquidityKind.UNBALANCED,
                expectedAmountsIn,
                expectedAmountsIn,
                _swapAmount,
                originalBalances,
                bytes("")
            )
        );

        router.addLiquidityUnbalanced(pool, expectedAmountsIn, _swapAmount, false, bytes(""));

        uint256 expectedBptOut = 0;
        for (uint256 i = 0; i < expectedAmountsIn.length; i++) {
            expectedBptOut += (expectedAmountsIn[i] + hookDiscount);
        }

        _checkAddLiquidityHookTestResults(testLocals, expectedAmountsIn, expectedBptOut, 0, hookDiscount);
    }

    //    function testOnBeforeSwapHookDiscountExactIn() public {
    //        HooksConfig memory hooksConfig = vault.getHooksConfig(address(pool));
    //        hooksConfig.shouldCallBeforeSwap = true;
    //        vault.setHooksConfig(address(pool), hooksConfig);
    //
    //        uint256[] memory originalBalances = [poolInitAmount, poolInitAmount].toMemoryArray();
    //
    //        uint256 hookDiscount = 1e3;
    //        PoolHooksMock(poolHooksContract).setOnBeforeSwapHookDiscount(hookDiscount);
    //
    //        // Hook needs to pay the discount to the pool. Since it's exact in, the discount is paid in tokenIn amount.
    //        dai.mint(address(poolHooksContract), hookDiscount);
    //
    //        uint256 daiBeforeBob = dai.balanceOf(address(bob));
    //        uint256 usdcBeforeBob = usdc.balanceOf(address(bob));
    //        uint256 daiBeforeHook = dai.balanceOf(address(poolHooksContract));
    //
    //        // Check that the swap gets updated balances that reflect the updated balance in the before hook
    //        vm.prank(bob);
    //        // Check if balances were not changed before onBeforeHook
    //        vm.expectCall(
    //            address(poolHooksContract),
    //            abi.encodeWithSelector(
    //                IHooks.onBeforeSwap.selector,
    //                IBasePool.PoolSwapParams({
    //                    kind: SwapKind.EXACT_IN,
    //                    amountGivenScaled18: _swapAmount,
    //                    balancesScaled18: originalBalances,
    //                    indexIn: daiIdx,
    //                    indexOut: usdcIdx,
    //                    router: address(router),
    //                    userData: bytes("")
    //                }),
    //                _swapAmount,
    //                address(pool)
    //            )
    //        );
    //
    //        vm.expectCall(
    //            address(pool),
    //            abi.encodeWithSelector(
    //                IBasePool.onSwap.selector,
    //                IBasePool.PoolSwapParams({
    //                    kind: SwapKind.EXACT_IN,
    //                    amountGivenScaled18: _swapAmount + hookDiscount,
    //                    balancesScaled18: originalBalances,
    //                    indexIn: daiIdx,
    //                    indexOut: usdcIdx,
    //                    router: address(router),
    //                    userData: bytes("")
    //                })
    //            )
    //        );
    //
    //        router.swapSingleTokenExactIn(address(pool), dai, usdc, _swapAmount, 0, MAX_UINT256, false, bytes(""));
    //
    //        uint256 daiAfterBob = dai.balanceOf(address(bob));
    //        uint256 usdcAfterBob = usdc.balanceOf(address(bob));
    //        uint256 daiAfterHook = dai.balanceOf(address(poolHooksContract));
    //
    //        assertEq(daiBeforeBob - daiAfterBob, _swapAmount, "Bob DAI balance is wrong");
    //        assertEq(usdcAfterBob - usdcBeforeBob, _swapAmount + hookDiscount, "Bob USDC balance is wrong");
    //        assertEq(daiBeforeHook - daiAfterHook, hookDiscount, "Hook DAI balance is wrong");
    //    }
    //
    //    function testOnBeforeSwapHookFeeExactOut() public {
    //        HooksConfig memory hooksConfig = vault.getHooksConfig(address(pool));
    //        hooksConfig.shouldCallBeforeSwap = true;
    //        vault.setHooksConfig(address(pool), hooksConfig);
    //
    //        uint256[] memory originalBalances = [poolInitAmount, poolInitAmount].toMemoryArray();
    //
    //        uint256 hookFee = 1e3;
    //        PoolHooksMock(poolHooksContract).setOnBeforeSwapHookFee(hookFee);
    //
    //        uint256 daiBeforeBob = dai.balanceOf(address(bob));
    //        uint256 usdcBeforeBob = usdc.balanceOf(address(bob));
    //        uint256 usdcBeforeHook = usdc.balanceOf(address(poolHooksContract));
    //
    //        // Check that the swap gets updated balances that reflect the updated balance in the before hook
    //        vm.prank(bob);
    //        // Check if balances were not changed before onBeforeHook
    //        vm.expectCall(
    //            address(poolHooksContract),
    //            abi.encodeWithSelector(
    //                IHooks.onBeforeSwap.selector,
    //                IBasePool.PoolSwapParams({
    //                    kind: SwapKind.EXACT_OUT,
    //                    amountGivenScaled18: _swapAmount,
    //                    balancesScaled18: originalBalances,
    //                    indexIn: daiIdx,
    //                    indexOut: usdcIdx,
    //                    router: address(router),
    //                    userData: bytes("")
    //                }),
    //                _swapAmount,
    //                address(pool)
    //            )
    //        );
    //
    //        vm.expectCall(
    //            address(pool),
    //            abi.encodeWithSelector(
    //                IBasePool.onSwap.selector,
    //                IBasePool.PoolSwapParams({
    //                    kind: SwapKind.EXACT_OUT,
    //                    amountGivenScaled18: _swapAmount + hookFee,
    //                    balancesScaled18: originalBalances,
    //                    indexIn: daiIdx,
    //                    indexOut: usdcIdx,
    //                    router: address(router),
    //                    userData: bytes("")
    //                })
    //            )
    //        );
    //
    //        router.swapSingleTokenExactOut(
    //            address(pool),
    //            dai,
    //            usdc,
    //            _swapAmount,
    //            MAX_UINT256,
    //            MAX_UINT256,
    //            false,
    //            bytes("")
    //        );
    //
    //        uint256 daiAfterBob = dai.balanceOf(address(bob));
    //        uint256 usdcAfterBob = usdc.balanceOf(address(bob));
    //        uint256 usdcAfterHook = usdc.balanceOf(address(poolHooksContract));
    //
    //        assertEq(daiBeforeBob - daiAfterBob, _swapAmount + hookFee, "Bob DAI balance is wrong");
    //        assertEq(usdcAfterBob - usdcBeforeBob, _swapAmount, "Bob USDC balance is wrong");
    //        assertEq(usdcAfterHook - usdcBeforeHook, hookFee, "Hook DAI balance is wrong");
    //    }
    //
    //    function testOnBeforeSwapHookDiscountExactOut() public {
    //        HooksConfig memory hooksConfig = vault.getHooksConfig(address(pool));
    //        hooksConfig.shouldCallBeforeSwap = true;
    //        vault.setHooksConfig(address(pool), hooksConfig);
    //
    //        uint256[] memory originalBalances = [poolInitAmount, poolInitAmount].toMemoryArray();
    //
    //        uint256 hookDiscount = 1e3;
    //        PoolHooksMock(poolHooksContract).setOnBeforeSwapHookDiscount(hookDiscount);
    //
    //        // Hook needs to pay the discount to the pool. Since it's exact out, the discount is paid in tokenOut amount.
    //        usdc.mint(address(poolHooksContract), hookDiscount);
    //
    //        uint256 daiBeforeBob = dai.balanceOf(address(bob));
    //        uint256 usdcBeforeBob = usdc.balanceOf(address(bob));
    //        uint256 usdcBeforeHook = usdc.balanceOf(address(poolHooksContract));
    //
    //        // Check that the swap gets updated balances that reflect the updated balance in the before hook
    //        vm.prank(bob);
    //        // Check if balances were not changed before onBeforeHook
    //        vm.expectCall(
    //            address(poolHooksContract),
    //            abi.encodeWithSelector(
    //                IHooks.onBeforeSwap.selector,
    //                IBasePool.PoolSwapParams({
    //                    kind: SwapKind.EXACT_OUT,
    //                    amountGivenScaled18: _swapAmount,
    //                    balancesScaled18: originalBalances,
    //                    indexIn: daiIdx,
    //                    indexOut: usdcIdx,
    //                    router: address(router),
    //                    userData: bytes("")
    //                }),
    //                _swapAmount,
    //                address(pool)
    //            )
    //        );
    //
    //        vm.expectCall(
    //            address(pool),
    //            abi.encodeWithSelector(
    //                IBasePool.onSwap.selector,
    //                IBasePool.PoolSwapParams({
    //                    kind: SwapKind.EXACT_OUT,
    //                    amountGivenScaled18: _swapAmount - hookDiscount,
    //                    balancesScaled18: originalBalances,
    //                    indexIn: daiIdx,
    //                    indexOut: usdcIdx,
    //                    router: address(router),
    //                    userData: bytes("")
    //                })
    //            )
    //        );
    //
    //        router.swapSingleTokenExactOut(
    //            address(pool),
    //            dai,
    //            usdc,
    //            _swapAmount,
    //            MAX_UINT256,
    //            MAX_UINT256,
    //            false,
    //            bytes("")
    //        );
    //
    //        uint256 daiAfterBob = dai.balanceOf(address(bob));
    //        uint256 usdcAfterBob = usdc.balanceOf(address(bob));
    //        uint256 usdcAfterHook = usdc.balanceOf(address(poolHooksContract));
    //
    //        assertEq(daiBeforeBob - daiAfterBob, _swapAmount - hookDiscount, "Bob DAI balance is wrong");
    //        assertEq(usdcAfterBob - usdcBeforeBob, _swapAmount, "Bob USDC balance is wrong");
    //        assertEq(usdcBeforeHook - usdcAfterHook, hookDiscount, "Hook DAI balance is wrong");
    //    }
    //
    //    function testOnAfterSwapHookFeeExactIn() public {
    //        HooksConfig memory hooksConfig = vault.getHooksConfig(address(pool));
    //        hooksConfig.shouldCallAfterSwap = true;
    //        vault.setHooksConfig(address(pool), hooksConfig);
    //
    //        uint256[] memory originalBalances = [poolInitAmount, poolInitAmount].toMemoryArray();
    //
    //        uint256 hookFee = 1e3;
    //        PoolHooksMock(poolHooksContract).setOnAfterSwapHookFee(hookFee);
    //
    //        uint256 daiBeforeBob = dai.balanceOf(address(bob));
    //        uint256 usdcBeforeBob = usdc.balanceOf(address(bob));
    //        uint256 usdcBeforeHook = usdc.balanceOf(address(poolHooksContract));
    //
    //        // Check that the swap gets updated balances that reflect the updated balance in the before hook
    //        vm.prank(bob);
    //        // Check if balances were not changed before onBeforeHook
    //        vm.expectCall(
    //            address(poolHooksContract),
    //            abi.encodeWithSelector(
    //                IHooks.onAfterSwap.selector,
    //                IHooks.AfterSwapParams({
    //                    kind: SwapKind.EXACT_IN,
    //                    tokenIn: dai,
    //                    tokenOut: usdc,
    //                    amountInScaled18: _swapAmount,
    //                    amountOutScaled18: _swapAmount,
    //                    tokenInBalanceScaled18: poolInitAmount + _swapAmount,
    //                    tokenOutBalanceScaled18: poolInitAmount - _swapAmount,
    //                    amountCalculatedScaled18: _swapAmount,
    //                    amountCalculatedRaw: _swapAmount,
    //                    router: address(router),
    //                    pool: pool,
    //                    userData: ""
    //                })
    //            )
    //        );
    //
    //        router.swapSingleTokenExactIn(address(pool), dai, usdc, _swapAmount, 0, MAX_UINT256, false, bytes(""));
    //
    //        uint256 daiAfterBob = dai.balanceOf(address(bob));
    //        uint256 usdcAfterBob = usdc.balanceOf(address(bob));
    //        uint256 usdcAfterHook = usdc.balanceOf(address(poolHooksContract));
    //
    //        assertEq(daiBeforeBob - daiAfterBob, _swapAmount, "Bob DAI balance is wrong");
    //        assertEq(usdcAfterBob - usdcBeforeBob, _swapAmount - hookFee, "Bob USDC balance is wrong");
    //        assertEq(usdcAfterHook - usdcBeforeHook, hookFee, "Hook USDC balance is wrong");
    //    }
    //
    //    function testOnAfterSwapHookDiscountExactIn() public {
    //        HooksConfig memory hooksConfig = vault.getHooksConfig(address(pool));
    //        hooksConfig.shouldCallAfterSwap = true;
    //        vault.setHooksConfig(address(pool), hooksConfig);
    //
    //        uint256[] memory originalBalances = [poolInitAmount, poolInitAmount].toMemoryArray();
    //
    //        uint256 hookDiscount = 1e3;
    //        PoolHooksMock(poolHooksContract).setOnAfterSwapHookDiscount(hookDiscount);
    //
    //        // Hook needs to pay the discount to the pool. Since it's exact in, the discount is paid in tokenOut amount.
    //        usdc.mint(address(poolHooksContract), hookDiscount);
    //
    //        uint256 daiBeforeBob = dai.balanceOf(address(bob));
    //        uint256 usdcBeforeBob = usdc.balanceOf(address(bob));
    //        uint256 usdcBeforeHook = usdc.balanceOf(address(poolHooksContract));
    //
    //        // Check that the swap gets updated balances that reflect the updated balance in the before hook
    //        vm.prank(bob);
    //        // Check if balances were not changed before onBeforeHook
    //        vm.expectCall(
    //            address(poolHooksContract),
    //            abi.encodeWithSelector(
    //                IHooks.onAfterSwap.selector,
    //                IHooks.AfterSwapParams({
    //                    kind: SwapKind.EXACT_IN,
    //                    tokenIn: dai,
    //                    tokenOut: usdc,
    //                    amountInScaled18: _swapAmount,
    //                    amountOutScaled18: _swapAmount,
    //                    tokenInBalanceScaled18: poolInitAmount + _swapAmount,
    //                    tokenOutBalanceScaled18: poolInitAmount - _swapAmount,
    //                    amountCalculatedScaled18: _swapAmount,
    //                    amountCalculatedRaw: _swapAmount,
    //                    router: address(router),
    //                    pool: pool,
    //                    userData: ""
    //                })
    //            )
    //        );
    //
    //        router.swapSingleTokenExactIn(address(pool), dai, usdc, _swapAmount, 0, MAX_UINT256, false, bytes(""));
    //
    //        uint256 daiAfterBob = dai.balanceOf(address(bob));
    //        uint256 usdcAfterBob = usdc.balanceOf(address(bob));
    //        uint256 usdcAfterHook = usdc.balanceOf(address(poolHooksContract));
    //
    //        assertEq(daiBeforeBob - daiAfterBob, _swapAmount, "Bob DAI balance is wrong");
    //        assertEq(usdcAfterBob - usdcBeforeBob, _swapAmount + hookDiscount, "Bob USDC balance is wrong");
    //        assertEq(usdcBeforeHook - usdcAfterHook, hookDiscount, "Hook USDC balance is wrong");
    //    }
    //
    //    function testOnAfterSwapHookFeeExactOut() public {
    //        HooksConfig memory hooksConfig = vault.getHooksConfig(address(pool));
    //        hooksConfig.shouldCallAfterSwap = true;
    //        vault.setHooksConfig(address(pool), hooksConfig);
    //
    //        uint256[] memory originalBalances = [poolInitAmount, poolInitAmount].toMemoryArray();
    //
    //        uint256 hookFee = 1e3;
    //        PoolHooksMock(poolHooksContract).setOnAfterSwapHookFee(hookFee);
    //
    //        uint256 daiBeforeBob = dai.balanceOf(address(bob));
    //        uint256 usdcBeforeBob = usdc.balanceOf(address(bob));
    //        uint256 daiBeforeHook = dai.balanceOf(address(poolHooksContract));
    //
    //        // Check that the swap gets updated balances that reflect the updated balance in the before hook
    //        vm.prank(bob);
    //        // Check if balances were not changed before onBeforeHook
    //        vm.expectCall(
    //            address(poolHooksContract),
    //            abi.encodeWithSelector(
    //                IHooks.onAfterSwap.selector,
    //                IHooks.AfterSwapParams({
    //                    kind: SwapKind.EXACT_OUT,
    //                    tokenIn: dai,
    //                    tokenOut: usdc,
    //                    amountInScaled18: _swapAmount,
    //                    amountOutScaled18: _swapAmount,
    //                    tokenInBalanceScaled18: poolInitAmount + _swapAmount,
    //                    tokenOutBalanceScaled18: poolInitAmount - _swapAmount,
    //                    amountCalculatedScaled18: _swapAmount,
    //                    amountCalculatedRaw: _swapAmount,
    //                    router: address(router),
    //                    pool: pool,
    //                    userData: ""
    //                })
    //            )
    //        );
    //
    //        router.swapSingleTokenExactOut(
    //            address(pool),
    //            dai,
    //            usdc,
    //            _swapAmount,
    //            MAX_UINT256,
    //            MAX_UINT256,
    //            false,
    //            bytes("")
    //        );
    //
    //        uint256 daiAfterBob = dai.balanceOf(address(bob));
    //        uint256 usdcAfterBob = usdc.balanceOf(address(bob));
    //        uint256 daiAfterHook = dai.balanceOf(address(poolHooksContract));
    //
    //        assertEq(daiBeforeBob - daiAfterBob, _swapAmount + hookFee, "Bob DAI balance is wrong");
    //        assertEq(usdcAfterBob - usdcBeforeBob, _swapAmount, "Bob USDC balance is wrong");
    //        assertEq(daiAfterHook - daiBeforeHook, hookFee, "Hook DAI balance is wrong");
    //    }
    //
    //    function testOnAfterSwapHookDiscountExactOut() public {
    //        HooksConfig memory hooksConfig = vault.getHooksConfig(address(pool));
    //        hooksConfig.shouldCallAfterSwap = true;
    //        vault.setHooksConfig(address(pool), hooksConfig);
    //
    //        uint256[] memory originalBalances = [poolInitAmount, poolInitAmount].toMemoryArray();
    //
    //        uint256 hookDiscount = 1e3;
    //        PoolHooksMock(poolHooksContract).setOnAfterSwapHookDiscount(hookDiscount);
    //
    //        // Hook needs to pay the discount to the pool. Since it's exact out, the discount is paid in tokenIn amount.
    //        dai.mint(address(poolHooksContract), hookDiscount);
    //
    //        uint256 daiBeforeBob = dai.balanceOf(address(bob));
    //        uint256 usdcBeforeBob = usdc.balanceOf(address(bob));
    //        uint256 daiBeforeHook = dai.balanceOf(address(poolHooksContract));
    //
    //        // Check that the swap gets updated balances that reflect the updated balance in the before hook
    //        vm.prank(bob);
    //        // Check if balances were not changed before onBeforeHook
    //        vm.expectCall(
    //            address(poolHooksContract),
    //            abi.encodeWithSelector(
    //                IHooks.onAfterSwap.selector,
    //                IHooks.AfterSwapParams({
    //                    kind: SwapKind.EXACT_OUT,
    //                    tokenIn: dai,
    //                    tokenOut: usdc,
    //                    amountInScaled18: _swapAmount,
    //                    amountOutScaled18: _swapAmount,
    //                    tokenInBalanceScaled18: poolInitAmount + _swapAmount,
    //                    tokenOutBalanceScaled18: poolInitAmount - _swapAmount,
    //                    amountCalculatedScaled18: _swapAmount,
    //                    amountCalculatedRaw: _swapAmount,
    //                    router: address(router),
    //                    pool: pool,
    //                    userData: ""
    //                })
    //            )
    //        );
    //
    //        router.swapSingleTokenExactOut(
    //            address(pool),
    //            dai,
    //            usdc,
    //            _swapAmount,
    //            MAX_UINT256,
    //            MAX_UINT256,
    //            false,
    //            bytes("")
    //        );
    //
    //        uint256 daiAfterBob = dai.balanceOf(address(bob));
    //        uint256 usdcAfterBob = usdc.balanceOf(address(bob));
    //        uint256 daiAfterHook = dai.balanceOf(address(poolHooksContract));
    //
    //        assertEq(daiBeforeBob - daiAfterBob, _swapAmount - hookDiscount, "Bob DAI balance is wrong");
    //        assertEq(usdcAfterBob - usdcBeforeBob, _swapAmount, "Bob USDC balance is wrong");
    //        assertEq(daiBeforeHook - daiAfterHook, hookDiscount, "Hook DAI balance is wrong");
    //    }

    struct HookTestLocals {
        uint256 daiBeforeBob;
        uint256 usdcBeforeBob;
        uint256 bptBeforeBob;
        uint256 daiBeforeHook;
        uint256 usdcBeforeHook;
        uint256[] poolBalancesBeforeHook;
        uint256 poolSupplyBeforeHook;
        uint256 daiAfterBob;
        uint256 usdcAfterBob;
        uint256 bptAfterBob;
        uint256 daiAfterHook;
        uint256 usdcAfterHook;
        uint256[] poolBalancesAfterHook;
        uint256 poolSupplyAfterHook;
    }

    function _createHookTestLocals() private returns (HookTestLocals memory testLocals) {
        testLocals.daiBeforeBob = dai.balanceOf(address(bob));
        testLocals.usdcBeforeBob = usdc.balanceOf(address(bob));
        testLocals.bptBeforeBob = IERC20(pool).balanceOf(address(bob));
        testLocals.daiBeforeHook = dai.balanceOf(address(poolHooksContract));
        testLocals.usdcBeforeHook = usdc.balanceOf(address(poolHooksContract));
        testLocals.poolBalancesBeforeHook = vault.getRawBalances(pool);
        testLocals.poolSupplyBeforeHook = BalancerPoolToken(pool).totalSupply();
    }

    function _checkAddLiquidityHookTestResults(
        HookTestLocals memory testLocals,
        uint256[] memory expectedAmountsIn,
        uint256 expectedBptOut,
        uint256 expectedHookFee,
        uint256 expectedHookDiscount
    ) private {
        testLocals.daiAfterBob = dai.balanceOf(address(bob));
        testLocals.usdcAfterBob = usdc.balanceOf(address(bob));
        testLocals.bptAfterBob = IERC20(pool).balanceOf(address(bob));
        testLocals.daiAfterHook = dai.balanceOf(address(poolHooksContract));
        testLocals.usdcAfterHook = usdc.balanceOf(address(poolHooksContract));
        testLocals.poolBalancesAfterHook = vault.getRawBalances(pool);
        testLocals.poolSupplyAfterHook = BalancerPoolToken(pool).totalSupply();

        assertEq(
            testLocals.daiBeforeBob - testLocals.daiAfterBob,
            expectedAmountsIn[daiIdx],
            "Bob DAI balance is wrong"
        );
        assertEq(
            testLocals.usdcBeforeBob - testLocals.usdcAfterBob,
            expectedAmountsIn[usdcIdx],
            "Bob USDC balance is wrong"
        );
        assertEq(testLocals.bptAfterBob - testLocals.bptBeforeBob, expectedBptOut, "Bob BPT balance is wrong");

        assertEq(
            testLocals.poolSupplyAfterHook - testLocals.poolSupplyBeforeHook,
            expectedBptOut,
            "Pool Supply is wrong"
        );

        if (expectedHookFee > 0) {
            assertEq(testLocals.daiAfterHook - testLocals.daiBeforeHook, expectedHookFee, "Hook DAI balance is wrong");
            assertEq(
                testLocals.usdcAfterHook - testLocals.usdcBeforeHook,
                expectedHookFee,
                "Hook USDC balance is wrong"
            );
            assertEq(
                testLocals.poolBalancesAfterHook[daiIdx] - testLocals.poolBalancesBeforeHook[daiIdx],
                expectedAmountsIn[daiIdx] - expectedHookFee,
                "Pool DAI balance is wrong"
            );
            assertEq(
                testLocals.poolBalancesAfterHook[usdcIdx] - testLocals.poolBalancesBeforeHook[usdcIdx],
                expectedAmountsIn[usdcIdx] - expectedHookFee,
                "Pool USDC balance is wrong"
            );
        } else if (expectedHookDiscount > 0) {
            assertEq(
                testLocals.daiBeforeHook - testLocals.daiAfterHook,
                expectedHookDiscount,
                "Hook DAI balance is wrong"
            );
            assertEq(
                testLocals.usdcBeforeHook - testLocals.usdcAfterHook,
                expectedHookDiscount,
                "Hook USDC balance is wrong"
            );
            assertEq(
            testLocals.poolBalancesAfterHook[daiIdx] - testLocals.poolBalancesBeforeHook[daiIdx],
                expectedAmountsIn[daiIdx] + expectedHookDiscount,
                "Pool DAI balance is wrong"
            );
            assertEq(
            testLocals.poolBalancesAfterHook[usdcIdx] - testLocals.poolBalancesBeforeHook[usdcIdx],
                expectedAmountsIn[usdcIdx] + expectedHookDiscount,
                "Pool USDC balance is wrong"
            );
        }
    }
}
