// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";

import { PoolHooksMock } from "../../contracts/test/PoolHooksMock.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract HooksOnAfterSwapFeesAndDiscountsTest is BaseVaultTest {
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

    function testFeeExactIn() public {
        HooksConfig memory hooksConfig = vault.getHooksConfig(address(pool));
        hooksConfig.shouldCallAfterSwap = true;
        vault.setHooksConfig(address(pool), hooksConfig);

        uint256[] memory originalBalances = [poolInitAmount, poolInitAmount].toMemoryArray();

        uint256 hookFee = 1e3;
        PoolHooksMock(poolHooksContract).setOnAfterSwapHookFee(hookFee);

        HookTestLocals memory vars = _createHookTestLocals();

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

        _fillAfterSwapHookTestLocals(vars);

        assertEq(vars.bob.daiBefore - vars.bob.daiAfter, _swapAmount, "Bob DAI balance is wrong");
        assertEq(vars.hook.daiBefore, vars.hook.daiAfter, "Hook DAI balance is wrong");
        assertEq(vars.bob.usdcAfter - vars.bob.usdcBefore, _swapAmount - hookFee, "Bob USDC balance is wrong");
        assertEq(vars.hook.usdcAfter - vars.hook.usdcBefore, hookFee, "Hook USDC balance is wrong");

        _checkPoolAndVaultBalances(vars, _swapAmount);
    }

    function testDiscountExactIn() public {
        HooksConfig memory hooksConfig = vault.getHooksConfig(address(pool));
        hooksConfig.shouldCallAfterSwap = true;
        vault.setHooksConfig(address(pool), hooksConfig);

        uint256[] memory originalBalances = [poolInitAmount, poolInitAmount].toMemoryArray();

        uint256 hookDiscount = 1e3;
        PoolHooksMock(poolHooksContract).setOnAfterSwapHookDiscount(hookDiscount);

        // Hook needs to pay the discount to the pool. Since it's exact in, the discount is paid in tokenOut amount.
        usdc.mint(address(poolHooksContract), hookDiscount);

        HookTestLocals memory vars = _createHookTestLocals();

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

        _fillAfterSwapHookTestLocals(vars);

        assertEq(vars.bob.daiBefore - vars.bob.daiAfter, _swapAmount, "Bob DAI balance is wrong");
        assertEq(vars.hook.daiBefore, vars.hook.daiAfter, "Hook DAI balance is wrong");
        assertEq(vars.bob.usdcAfter - vars.bob.usdcBefore, _swapAmount + hookDiscount, "Bob USDC balance is wrong");
        assertEq(vars.hook.usdcBefore - vars.hook.usdcAfter, hookDiscount, "Hook USDC balance is wrong");

        _checkPoolAndVaultBalances(vars, _swapAmount);
    }

    function testFeeExactOut() public {
        HooksConfig memory hooksConfig = vault.getHooksConfig(address(pool));
        hooksConfig.shouldCallAfterSwap = true;
        vault.setHooksConfig(address(pool), hooksConfig);

        uint256[] memory originalBalances = [poolInitAmount, poolInitAmount].toMemoryArray();

        uint256 hookFee = 1e3;
        PoolHooksMock(poolHooksContract).setOnAfterSwapHookFee(hookFee);

        HookTestLocals memory vars = _createHookTestLocals();

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

        _fillAfterSwapHookTestLocals(vars);

        assertEq(vars.bob.usdcAfter - vars.bob.usdcBefore, _swapAmount, "Bob USDC balance is wrong");
        assertEq(vars.hook.usdcBefore, vars.hook.usdcAfter, "Hook USDC balance is wrong");
        assertEq(vars.bob.daiBefore - vars.bob.daiAfter, _swapAmount + hookFee, "Bob DAI balance is wrong");
        assertEq(vars.hook.daiAfter - vars.hook.daiBefore, hookFee, "Hook DAI balance is wrong");

        _checkPoolAndVaultBalances(vars, _swapAmount);
    }

    function testDiscountExactOut() public {
        HooksConfig memory hooksConfig = vault.getHooksConfig(address(pool));
        hooksConfig.shouldCallAfterSwap = true;
        vault.setHooksConfig(address(pool), hooksConfig);

        uint256[] memory originalBalances = [poolInitAmount, poolInitAmount].toMemoryArray();

        uint256 hookDiscount = 1e3;
        PoolHooksMock(poolHooksContract).setOnAfterSwapHookDiscount(hookDiscount);

        // Hook needs to pay the discount to the pool. Since it's exact out, the discount is paid in tokenIn amount.
        dai.mint(address(poolHooksContract), hookDiscount);

        HookTestLocals memory vars = _createHookTestLocals();

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

        _fillAfterSwapHookTestLocals(vars);

        assertEq(vars.bob.usdcAfter - vars.bob.usdcBefore, _swapAmount, "Bob USDC balance is wrong");
        assertEq(vars.hook.usdcBefore, vars.hook.usdcAfter, "Hook USDC balance is wrong");
        assertEq(vars.bob.daiBefore - vars.bob.daiAfter, _swapAmount - hookDiscount, "Bob DAI balance is wrong");
        assertEq(vars.hook.daiBefore - vars.hook.daiAfter, hookDiscount, "Hook DAI balance is wrong");

        _checkPoolAndVaultBalances(vars, _swapAmount);
    }

    function testFeeExactInOutOfLimit() public {
        HooksConfig memory hooksConfig = vault.getHooksConfig(address(pool));
        hooksConfig.shouldCallAfterSwap = true;
        vault.setHooksConfig(address(pool), hooksConfig);

        uint256[] memory originalBalances = [poolInitAmount, poolInitAmount].toMemoryArray();

        uint256 hookFee = 1e3;
        PoolHooksMock(poolHooksContract).setOnAfterSwapHookFee(hookFee);

        // Check that the swap gets updated balances that reflect the updated balance in the before hook
        vm.prank(bob);
        // Check if onAfterHook was called with the correct params
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
        // Check if call reverted because limits were not respected in the after hook (amountOut < minAmountOut)
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.SwapLimit.selector, _swapAmount - hookFee, _swapAmount));

        router.swapSingleTokenExactIn(
            address(pool),
            dai,
            usdc,
            _swapAmount,
            _swapAmount,
            MAX_UINT256,
            false,
            bytes("")
        );
    }

    function testFeeExactOutOutOfLimit() public {
        HooksConfig memory hooksConfig = vault.getHooksConfig(address(pool));
        hooksConfig.shouldCallAfterSwap = true;
        vault.setHooksConfig(address(pool), hooksConfig);

        uint256[] memory originalBalances = [poolInitAmount, poolInitAmount].toMemoryArray();

        uint256 hookFee = 1e3;
        PoolHooksMock(poolHooksContract).setOnAfterSwapHookFee(hookFee);

        // Check that the swap gets updated balances that reflect the updated balance in the before hook
        vm.prank(bob);
        // Check if onAfterSwap was called with the correct parameters
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

        // Check if call reverted because limits were not respected in the after hook (amountIn > maxAmountIn)
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.SwapLimit.selector, _swapAmount + hookFee, _swapAmount));

        router.swapSingleTokenExactOut(
            address(pool),
            dai,
            usdc,
            _swapAmount,
            _swapAmount,
            MAX_UINT256,
            false,
            bytes("")
        );
    }

    struct WalletState {
        uint256 daiBefore;
        uint256 daiAfter;
        uint256 usdcBefore;
        uint256 usdcAfter;
    }

    struct HookTestLocals {
        WalletState bob;
        WalletState hook;
        WalletState vault;
        uint256[] poolBefore;
        uint256[] poolAfter;
    }

    function _createHookTestLocals() private returns (HookTestLocals memory vars) {
        vars.bob.daiBefore = dai.balanceOf(address(bob));
        vars.bob.usdcBefore = usdc.balanceOf(address(bob));
        vars.hook.daiBefore = dai.balanceOf(poolHooksContract);
        vars.hook.usdcBefore = usdc.balanceOf(poolHooksContract);
        vars.vault.daiBefore = dai.balanceOf(address(vault));
        vars.vault.usdcBefore = usdc.balanceOf(address(vault));
        vars.poolBefore = vault.getRawBalances(pool);
    }

    function _fillAfterSwapHookTestLocals(HookTestLocals memory vars) private {
        vars.bob.daiAfter = dai.balanceOf(address(bob));
        vars.bob.usdcAfter = usdc.balanceOf(address(bob));
        vars.hook.daiAfter = dai.balanceOf(poolHooksContract);
        vars.hook.usdcAfter = usdc.balanceOf(poolHooksContract);
        vars.vault.daiAfter = dai.balanceOf(address(vault));
        vars.vault.usdcAfter = usdc.balanceOf(address(vault));
        vars.poolAfter = vault.getRawBalances(pool);
    }

    function _checkPoolAndVaultBalances(HookTestLocals memory vars, uint256 poolBalanceChange) private {
        assertEq(vars.poolAfter[daiIdx] - vars.poolBefore[daiIdx], poolBalanceChange, "Pool DAI balance is wrong");
        assertEq(vars.poolBefore[usdcIdx] - vars.poolAfter[usdcIdx], poolBalanceChange, "Pool USDC balance is wrong");
        assertEq(vars.vault.daiAfter - vars.vault.daiBefore, poolBalanceChange, "Vault DAI balance is wrong");
        assertEq(vars.vault.usdcBefore - vars.vault.usdcAfter, poolBalanceChange, "Vault USDC balance is wrong");
    }
}
