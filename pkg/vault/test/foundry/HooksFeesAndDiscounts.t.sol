// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";

import { PoolHooksMock } from "../../contracts/test/PoolHooksMock.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract HooksFeesAndDiscountsTest is BaseVaultTest {
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

    function testOnBeforeSwapHookFeeExactIn() public {
        HooksConfig memory hooksConfig = vault.getHooksConfig(address(pool));
        hooksConfig.shouldCallBeforeSwap = true;
        vault.setHooksConfig(address(pool), hooksConfig);

        uint256[] memory originalBalances = [poolInitAmount, poolInitAmount].toMemoryArray();

        uint256 hookFee = 1e3;
        PoolHooksMock(poolHooksContract).setOnBeforeSwapHookFee(hookFee);

        uint256 daiBeforeBob = dai.balanceOf(address(bob));
        uint256 usdcBeforeBob = usdc.balanceOf(address(bob));
        uint256 daiBeforeHook = dai.balanceOf(address(poolHooksContract));

        // Check that the swap gets updated balances that reflect the updated balance in the before hook
        vm.prank(bob);
        // Check if balances were not changed before onBeforeHook
        vm.expectCall(
            address(poolHooksContract),
            abi.encodeWithSelector(
                IHooks.onBeforeSwap.selector,
                IBasePool.PoolSwapParams({
                    kind: SwapKind.EXACT_IN,
                    amountGivenScaled18: _swapAmount,
                    amountGivenRaw: _swapAmount,
                    balancesScaled18: originalBalances,
                    indexIn: daiIdx,
                    indexOut: usdcIdx,
                    router: address(router),
                    userData: bytes("")
                }),
                address(pool)
            )
        );

        vm.expectCall(
            address(pool),
            abi.encodeWithSelector(
                IBasePool.onSwap.selector,
                IBasePool.PoolSwapParams({
                    kind: SwapKind.EXACT_IN,
                    amountGivenScaled18: _swapAmount - hookFee,
                    amountGivenRaw: _swapAmount - hookFee,
                    balancesScaled18: originalBalances,
                    indexIn: daiIdx,
                    indexOut: usdcIdx,
                    router: address(router),
                    userData: bytes("")
                })
            )
        );

        router.swapSingleTokenExactIn(address(pool), dai, usdc, _swapAmount, 0, MAX_UINT256, false, bytes(""));

        uint256 daiAfterBob = dai.balanceOf(address(bob));
        uint256 usdcAfterBob = usdc.balanceOf(address(bob));
        uint256 daiAfterHook = dai.balanceOf(address(poolHooksContract));

        assertEq(daiBeforeBob - daiAfterBob, _swapAmount, "Bob DAI balance is wrong");
        assertEq(usdcAfterBob - usdcBeforeBob, _swapAmount - hookFee, "Bob USDC balance is wrong");
        assertEq(daiAfterHook - daiBeforeHook, hookFee, "Hook DAI balance is wrong");
    }

    function testOnBeforeSwapHookDiscountExactIn() public {
        HooksConfig memory hooksConfig = vault.getHooksConfig(address(pool));
        hooksConfig.shouldCallBeforeSwap = true;
        vault.setHooksConfig(address(pool), hooksConfig);

        uint256[] memory originalBalances = [poolInitAmount, poolInitAmount].toMemoryArray();

        uint256 hookDiscount = 1e3;
        PoolHooksMock(poolHooksContract).setOnBeforeSwapHookDiscount(hookDiscount);

        // Hook needs to pay the discount to the pool. Since it's exact in, the discount is paid in tokenIn amount.
        dai.mint(address(poolHooksContract), hookDiscount);

        uint256 daiBeforeBob = dai.balanceOf(address(bob));
        uint256 usdcBeforeBob = usdc.balanceOf(address(bob));
        uint256 daiBeforeHook = dai.balanceOf(address(poolHooksContract));

        // Check that the swap gets updated balances that reflect the updated balance in the before hook
        vm.prank(bob);
        // Check if balances were not changed before onBeforeHook
        vm.expectCall(
            address(poolHooksContract),
            abi.encodeWithSelector(
                IHooks.onBeforeSwap.selector,
                IBasePool.PoolSwapParams({
                    kind: SwapKind.EXACT_IN,
                    amountGivenScaled18: _swapAmount,
                    amountGivenRaw: _swapAmount,
                    balancesScaled18: originalBalances,
                    indexIn: daiIdx,
                    indexOut: usdcIdx,
                    router: address(router),
                    userData: bytes("")
                }),
                address(pool)
            )
        );

        vm.expectCall(
            address(pool),
            abi.encodeWithSelector(
                IBasePool.onSwap.selector,
                IBasePool.PoolSwapParams({
                    kind: SwapKind.EXACT_IN,
                    amountGivenScaled18: _swapAmount + hookDiscount,
                    amountGivenRaw: _swapAmount + hookDiscount,
                    balancesScaled18: originalBalances,
                    indexIn: daiIdx,
                    indexOut: usdcIdx,
                    router: address(router),
                    userData: bytes("")
                })
            )
        );

        router.swapSingleTokenExactIn(address(pool), dai, usdc, _swapAmount, 0, MAX_UINT256, false, bytes(""));

        uint256 daiAfterBob = dai.balanceOf(address(bob));
        uint256 usdcAfterBob = usdc.balanceOf(address(bob));
        uint256 daiAfterHook = dai.balanceOf(address(poolHooksContract));

        assertEq(daiBeforeBob - daiAfterBob, _swapAmount, "Bob DAI balance is wrong");
        assertEq(usdcAfterBob - usdcBeforeBob, _swapAmount + hookDiscount, "Bob USDC balance is wrong");
        assertEq(daiBeforeHook - daiAfterHook, hookDiscount, "Hook DAI balance is wrong");
    }

    function testOnBeforeSwapHookFeeExactOut() public {
        HooksConfig memory hooksConfig = vault.getHooksConfig(address(pool));
        hooksConfig.shouldCallBeforeSwap = true;
        vault.setHooksConfig(address(pool), hooksConfig);

        uint256[] memory originalBalances = [poolInitAmount, poolInitAmount].toMemoryArray();

        uint256 hookFee = 1e3;
        PoolHooksMock(poolHooksContract).setOnBeforeSwapHookFee(hookFee);

        uint256 daiBeforeBob = dai.balanceOf(address(bob));
        uint256 usdcBeforeBob = usdc.balanceOf(address(bob));
        uint256 usdcBeforeHook = usdc.balanceOf(address(poolHooksContract));

        // Check that the swap gets updated balances that reflect the updated balance in the before hook
        vm.prank(bob);
        // Check if balances were not changed before onBeforeHook
        vm.expectCall(
            address(poolHooksContract),
            abi.encodeWithSelector(
                IHooks.onBeforeSwap.selector,
                IBasePool.PoolSwapParams({
                    kind: SwapKind.EXACT_OUT,
                    amountGivenScaled18: _swapAmount,
                    amountGivenRaw: _swapAmount,
                    balancesScaled18: originalBalances,
                    indexIn: daiIdx,
                    indexOut: usdcIdx,
                    router: address(router),
                    userData: bytes("")
                }),
                address(pool)
            )
        );

        vm.expectCall(
            address(pool),
            abi.encodeWithSelector(
                IBasePool.onSwap.selector,
                IBasePool.PoolSwapParams({
                    kind: SwapKind.EXACT_OUT,
                    amountGivenScaled18: _swapAmount + hookFee,
                    amountGivenRaw: _swapAmount + hookFee,
                    balancesScaled18: originalBalances,
                    indexIn: daiIdx,
                    indexOut: usdcIdx,
                    router: address(router),
                    userData: bytes("")
                })
            )
        );

        router.swapSingleTokenExactOut(
            address(pool),
            dai,
            usdc,
            _swapAmount,
            MAX_UINT256,
            MAX_UINT256,
            false,
            bytes("")
        );

        uint256 daiAfterBob = dai.balanceOf(address(bob));
        uint256 usdcAfterBob = usdc.balanceOf(address(bob));
        uint256 usdcAfterHook = usdc.balanceOf(address(poolHooksContract));

        assertEq(daiBeforeBob - daiAfterBob, _swapAmount + hookFee, "Bob DAI balance is wrong");
        assertEq(usdcAfterBob - usdcBeforeBob, _swapAmount, "Bob USDC balance is wrong");
        assertEq(usdcAfterHook - usdcBeforeHook, hookFee, "Hook DAI balance is wrong");
    }

    function testOnBeforeSwapHookDiscountExactOut() public {
        HooksConfig memory hooksConfig = vault.getHooksConfig(address(pool));
        hooksConfig.shouldCallBeforeSwap = true;
        vault.setHooksConfig(address(pool), hooksConfig);

        uint256[] memory originalBalances = [poolInitAmount, poolInitAmount].toMemoryArray();

        uint256 hookDiscount = 1e3;
        PoolHooksMock(poolHooksContract).setOnBeforeSwapHookDiscount(hookDiscount);

        // Hook needs to pay the discount to the pool. Since it's exact out, the discount is paid in tokenOut amount.
        usdc.mint(address(poolHooksContract), hookDiscount);

        uint256 daiBeforeBob = dai.balanceOf(address(bob));
        uint256 usdcBeforeBob = usdc.balanceOf(address(bob));
        uint256 usdcBeforeHook = usdc.balanceOf(address(poolHooksContract));

        // Check that the swap gets updated balances that reflect the updated balance in the before hook
        vm.prank(bob);
        // Check if balances were not changed before onBeforeHook
        vm.expectCall(
            address(poolHooksContract),
            abi.encodeWithSelector(
                IHooks.onBeforeSwap.selector,
                IBasePool.PoolSwapParams({
                    kind: SwapKind.EXACT_OUT,
                    amountGivenScaled18: _swapAmount,
                    amountGivenRaw: _swapAmount,
                    balancesScaled18: originalBalances,
                    indexIn: daiIdx,
                    indexOut: usdcIdx,
                    router: address(router),
                    userData: bytes("")
                }),
                address(pool)
            )
        );

        vm.expectCall(
            address(pool),
            abi.encodeWithSelector(
                IBasePool.onSwap.selector,
                IBasePool.PoolSwapParams({
                    kind: SwapKind.EXACT_OUT,
                    amountGivenScaled18: _swapAmount - hookDiscount,
                    amountGivenRaw: _swapAmount - hookDiscount,
                    balancesScaled18: originalBalances,
                    indexIn: daiIdx,
                    indexOut: usdcIdx,
                    router: address(router),
                    userData: bytes("")
                })
            )
        );

        router.swapSingleTokenExactOut(
            address(pool),
            dai,
            usdc,
            _swapAmount,
            MAX_UINT256,
            MAX_UINT256,
            false,
            bytes("")
        );

        uint256 daiAfterBob = dai.balanceOf(address(bob));
        uint256 usdcAfterBob = usdc.balanceOf(address(bob));
        uint256 usdcAfterHook = usdc.balanceOf(address(poolHooksContract));

        assertEq(daiBeforeBob - daiAfterBob, _swapAmount - hookDiscount, "Bob DAI balance is wrong");
        assertEq(usdcAfterBob - usdcBeforeBob, _swapAmount, "Bob USDC balance is wrong");
        assertEq(usdcBeforeHook - usdcAfterHook, hookDiscount, "Hook DAI balance is wrong");
    }

    function testOnAfterSwapHookFeeExactIn() public {
        HooksConfig memory hooksConfig = vault.getHooksConfig(address(pool));
        hooksConfig.shouldCallAfterSwap = true;
        vault.setHooksConfig(address(pool), hooksConfig);

        uint256[] memory originalBalances = [poolInitAmount, poolInitAmount].toMemoryArray();

        uint256 hookFee = 1e3;
        PoolHooksMock(poolHooksContract).setOnAfterSwapHookFee(hookFee);

        uint256 daiBeforeBob = dai.balanceOf(address(bob));
        uint256 usdcBeforeBob = usdc.balanceOf(address(bob));
        uint256 usdcBeforeHook = usdc.balanceOf(address(poolHooksContract));

        // Check that the swap gets updated balances that reflect the updated balance in the before hook
        vm.prank(bob);
        // Check if balances were not changed before onBeforeHook
        vm.expectCall(
            address(poolHooksContract),
            abi.encodeWithSelector(
                IHooks.onAfterSwap.selector,
                IHooks.AfterSwapParams({
                    kind: SwapKind.EXACT_IN,
                    tokenIn: dai,
                    tokenOut: usdc,
                    amountInScaled18: _swapAmount,
                    amountOutScaled18: _swapAmount,
                    tokenInBalanceScaled18: poolInitAmount + _swapAmount,
                    tokenOutBalanceScaled18: poolInitAmount - _swapAmount,
                    amountCalculatedScaled18: _swapAmount,
                    amountCalculatedRaw: _swapAmount,
                    router: address(router),
                    pool: pool,
                    userData: ""
                })
            )
        );

        router.swapSingleTokenExactIn(address(pool), dai, usdc, _swapAmount, 0, MAX_UINT256, false, bytes(""));

        uint256 daiAfterBob = dai.balanceOf(address(bob));
        uint256 usdcAfterBob = usdc.balanceOf(address(bob));
        uint256 usdcAfterHook = usdc.balanceOf(address(poolHooksContract));

        assertEq(daiBeforeBob - daiAfterBob, _swapAmount, "Bob DAI balance is wrong");
        assertEq(usdcAfterBob - usdcBeforeBob, _swapAmount - hookFee, "Bob USDC balance is wrong");
        assertEq(usdcAfterHook - usdcBeforeHook, hookFee, "Hook USDC balance is wrong");
    }

    function testOnAfterSwapHookDiscountExactIn() public {
        HooksConfig memory hooksConfig = vault.getHooksConfig(address(pool));
        hooksConfig.shouldCallAfterSwap = true;
        vault.setHooksConfig(address(pool), hooksConfig);

        uint256[] memory originalBalances = [poolInitAmount, poolInitAmount].toMemoryArray();

        uint256 hookDiscount = 1e3;
        PoolHooksMock(poolHooksContract).setOnAfterSwapHookDiscount(hookDiscount);

        // Hook needs to pay the discount to the pool. Since it's exact in, the discount is paid in tokenOut amount.
        usdc.mint(address(poolHooksContract), hookDiscount);

        uint256 daiBeforeBob = dai.balanceOf(address(bob));
        uint256 usdcBeforeBob = usdc.balanceOf(address(bob));
        uint256 usdcBeforeHook = usdc.balanceOf(address(poolHooksContract));

        // Check that the swap gets updated balances that reflect the updated balance in the before hook
        vm.prank(bob);
        // Check if balances were not changed before onBeforeHook
        vm.expectCall(
            address(poolHooksContract),
            abi.encodeWithSelector(
                IHooks.onAfterSwap.selector,
                IHooks.AfterSwapParams({
                    kind: SwapKind.EXACT_IN,
                    tokenIn: dai,
                    tokenOut: usdc,
                    amountInScaled18: _swapAmount,
                    amountOutScaled18: _swapAmount,
                    tokenInBalanceScaled18: poolInitAmount + _swapAmount,
                    tokenOutBalanceScaled18: poolInitAmount - _swapAmount,
                    amountCalculatedScaled18: _swapAmount,
                    amountCalculatedRaw: _swapAmount,
                    router: address(router),
                    pool: pool,
                    userData: ""
                })
            )
        );

        router.swapSingleTokenExactIn(address(pool), dai, usdc, _swapAmount, 0, MAX_UINT256, false, bytes(""));

        uint256 daiAfterBob = dai.balanceOf(address(bob));
        uint256 usdcAfterBob = usdc.balanceOf(address(bob));
        uint256 usdcAfterHook = usdc.balanceOf(address(poolHooksContract));

        assertEq(daiBeforeBob - daiAfterBob, _swapAmount, "Bob DAI balance is wrong");
        assertEq(usdcAfterBob - usdcBeforeBob, _swapAmount + hookDiscount, "Bob USDC balance is wrong");
        assertEq(usdcBeforeHook - usdcAfterHook, hookDiscount, "Hook USDC balance is wrong");
    }

    function testOnAfterSwapHookFeeExactOut() public {
        HooksConfig memory hooksConfig = vault.getHooksConfig(address(pool));
        hooksConfig.shouldCallAfterSwap = true;
        vault.setHooksConfig(address(pool), hooksConfig);

        uint256[] memory originalBalances = [poolInitAmount, poolInitAmount].toMemoryArray();

        uint256 hookFee = 1e3;
        PoolHooksMock(poolHooksContract).setOnAfterSwapHookFee(hookFee);

        uint256 daiBeforeBob = dai.balanceOf(address(bob));
        uint256 usdcBeforeBob = usdc.balanceOf(address(bob));
        uint256 daiBeforeHook = dai.balanceOf(address(poolHooksContract));

        // Check that the swap gets updated balances that reflect the updated balance in the before hook
        vm.prank(bob);
        // Check if balances were not changed before onBeforeHook
        vm.expectCall(
            address(poolHooksContract),
            abi.encodeWithSelector(
                IHooks.onAfterSwap.selector,
                IHooks.AfterSwapParams({
                    kind: SwapKind.EXACT_OUT,
                    tokenIn: dai,
                    tokenOut: usdc,
                    amountInScaled18: _swapAmount,
                    amountOutScaled18: _swapAmount,
                    tokenInBalanceScaled18: poolInitAmount + _swapAmount,
                    tokenOutBalanceScaled18: poolInitAmount - _swapAmount,
                    amountCalculatedScaled18: _swapAmount,
                    amountCalculatedRaw: _swapAmount,
                    router: address(router),
                    pool: pool,
                    userData: ""
                })
            )
        );

        router.swapSingleTokenExactOut(
            address(pool),
            dai,
            usdc,
            _swapAmount,
            MAX_UINT256,
            MAX_UINT256,
            false,
            bytes("")
        );

        uint256 daiAfterBob = dai.balanceOf(address(bob));
        uint256 usdcAfterBob = usdc.balanceOf(address(bob));
        uint256 daiAfterHook = dai.balanceOf(address(poolHooksContract));

        assertEq(daiBeforeBob - daiAfterBob, _swapAmount + hookFee, "Bob DAI balance is wrong");
        assertEq(usdcAfterBob - usdcBeforeBob, _swapAmount, "Bob USDC balance is wrong");
        assertEq(daiAfterHook - daiBeforeHook, hookFee, "Hook DAI balance is wrong");
    }

    function testOnAfterSwapHookDiscountExactOut() public {
        HooksConfig memory hooksConfig = vault.getHooksConfig(address(pool));
        hooksConfig.shouldCallAfterSwap = true;
        vault.setHooksConfig(address(pool), hooksConfig);

        uint256[] memory originalBalances = [poolInitAmount, poolInitAmount].toMemoryArray();

        uint256 hookDiscount = 1e3;
        PoolHooksMock(poolHooksContract).setOnAfterSwapHookDiscount(hookDiscount);

        // Hook needs to pay the discount to the pool. Since it's exact out, the discount is paid in tokenIn amount.
        dai.mint(address(poolHooksContract), hookDiscount);

        uint256 daiBeforeBob = dai.balanceOf(address(bob));
        uint256 usdcBeforeBob = usdc.balanceOf(address(bob));
        uint256 daiBeforeHook = dai.balanceOf(address(poolHooksContract));

        // Check that the swap gets updated balances that reflect the updated balance in the before hook
        vm.prank(bob);
        // Check if balances were not changed before onBeforeHook
        vm.expectCall(
            address(poolHooksContract),
            abi.encodeWithSelector(
                IHooks.onAfterSwap.selector,
                IHooks.AfterSwapParams({
                    kind: SwapKind.EXACT_OUT,
                    tokenIn: dai,
                    tokenOut: usdc,
                    amountInScaled18: _swapAmount,
                    amountOutScaled18: _swapAmount,
                    tokenInBalanceScaled18: poolInitAmount + _swapAmount,
                    tokenOutBalanceScaled18: poolInitAmount - _swapAmount,
                    amountCalculatedScaled18: _swapAmount,
                    amountCalculatedRaw: _swapAmount,
                    router: address(router),
                    pool: pool,
                    userData: ""
                })
            )
        );

        router.swapSingleTokenExactOut(
            address(pool),
            dai,
            usdc,
            _swapAmount,
            MAX_UINT256,
            MAX_UINT256,
            false,
            bytes("")
        );

        uint256 daiAfterBob = dai.balanceOf(address(bob));
        uint256 usdcAfterBob = usdc.balanceOf(address(bob));
        uint256 daiAfterHook = dai.balanceOf(address(poolHooksContract));

        assertEq(daiBeforeBob - daiAfterBob, _swapAmount - hookDiscount, "Bob DAI balance is wrong");
        assertEq(usdcAfterBob - usdcBeforeBob, _swapAmount, "Bob USDC balance is wrong");
        assertEq(daiBeforeHook - daiAfterHook, hookDiscount, "Hook DAI balance is wrong");
    }
}
