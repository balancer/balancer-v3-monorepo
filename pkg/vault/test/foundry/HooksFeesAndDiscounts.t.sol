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

        HookTestLocals memory vars = _createHookTestLocals();

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
                    balancesScaled18: originalBalances,
                    indexIn: daiIdx,
                    indexOut: usdcIdx,
                    router: address(router),
                    userData: bytes("")
                }),
                _swapAmount,
                pool
            )
        );

        vm.expectCall(
            address(pool),
            abi.encodeWithSelector(
                IBasePool.onSwap.selector,
                IBasePool.PoolSwapParams({
                    kind: SwapKind.EXACT_IN,
                    amountGivenScaled18: _swapAmount - hookFee,
                    balancesScaled18: originalBalances,
                    indexIn: daiIdx,
                    indexOut: usdcIdx,
                    router: address(router),
                    userData: bytes("")
                })
            )
        );

        router.swapSingleTokenExactIn(address(pool), dai, usdc, _swapAmount, 0, MAX_UINT256, false, bytes(""));

        _checkSwapHookTestResults(vars, SwapKind.EXACT_IN, true, _swapAmount, hookFee, 0);
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

        HookTestLocals memory vars = _createHookTestLocals();

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
                    balancesScaled18: originalBalances,
                    indexIn: daiIdx,
                    indexOut: usdcIdx,
                    router: address(router),
                    userData: bytes("")
                }),
                _swapAmount,
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
                    balancesScaled18: originalBalances,
                    indexIn: daiIdx,
                    indexOut: usdcIdx,
                    router: address(router),
                    userData: bytes("")
                })
            )
        );

        router.swapSingleTokenExactIn(address(pool), dai, usdc, _swapAmount, 0, MAX_UINT256, false, bytes(""));

        _checkSwapHookTestResults(vars, SwapKind.EXACT_IN, true, _swapAmount, 0, hookDiscount);
    }

    function testOnBeforeSwapHookFeeExactOut() public {
        HooksConfig memory hooksConfig = vault.getHooksConfig(address(pool));
        hooksConfig.shouldCallBeforeSwap = true;
        vault.setHooksConfig(address(pool), hooksConfig);

        uint256[] memory originalBalances = [poolInitAmount, poolInitAmount].toMemoryArray();

        uint256 hookFee = 1e3;
        PoolHooksMock(poolHooksContract).setOnBeforeSwapHookFee(hookFee);

        HookTestLocals memory vars = _createHookTestLocals();

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
                    balancesScaled18: originalBalances,
                    indexIn: daiIdx,
                    indexOut: usdcIdx,
                    router: address(router),
                    userData: bytes("")
                }),
                _swapAmount,
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

        _checkSwapHookTestResults(vars, SwapKind.EXACT_OUT, true, _swapAmount, hookFee, 0);
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

        HookTestLocals memory vars = _createHookTestLocals();

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
                    balancesScaled18: originalBalances,
                    indexIn: daiIdx,
                    indexOut: usdcIdx,
                    router: address(router),
                    userData: bytes("")
                }),
                _swapAmount,
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

        _checkSwapHookTestResults(vars, SwapKind.EXACT_OUT, true, _swapAmount, 0, hookDiscount);
    }

    function testOnAfterSwapHookFeeExactIn() public {
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

        _checkSwapHookTestResults(vars, SwapKind.EXACT_IN, false, _swapAmount, hookFee, 0);
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

        _checkSwapHookTestResults(vars, SwapKind.EXACT_IN, false, _swapAmount, 0, hookDiscount);
    }

    function testOnAfterSwapHookFeeExactOut() public {
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

        _checkSwapHookTestResults(vars, SwapKind.EXACT_OUT, false, _swapAmount, hookFee, 0);
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

        _checkSwapHookTestResults(vars, SwapKind.EXACT_OUT, false, _swapAmount, 0, hookDiscount);
    }

    struct HookTestLocals {
        uint256 daiBeforeBob;
        uint256 usdcBeforeBob;
        uint256 daiBeforeHook;
        uint256 usdcBeforeHook;
        uint256 daiBeforeVault;
        uint256 usdcBeforeVault;
        uint256[] poolBalancesBefore;
        uint256 daiAfterBob;
        uint256 usdcAfterBob;
        uint256 daiAfterHook;
        uint256 usdcAfterHook;
        uint256 daiAfterVault;
        uint256 usdcAfterVault;
        uint256[] poolBalancesAfter;
    }

    function _createHookTestLocals() private returns (HookTestLocals memory vars) {
        vars.daiBeforeBob = dai.balanceOf(address(bob));
        vars.usdcBeforeBob = usdc.balanceOf(address(bob));
        vars.daiBeforeHook = dai.balanceOf(poolHooksContract);
        vars.usdcBeforeHook = usdc.balanceOf(poolHooksContract);
        vars.daiBeforeVault = dai.balanceOf(address(vault));
        vars.usdcBeforeVault = usdc.balanceOf(address(vault));
        vars.poolBalancesBefore = vault.getRawBalances(pool);
    }

    function _checkSwapHookTestResults(
        HookTestLocals memory vars,
        SwapKind kind,
        bool isBeforeHook,
        uint256 swapAmount,
        uint256 hookFee,
        uint256 hookDiscount
    ) private {
        vars.daiAfterBob = dai.balanceOf(address(bob));
        vars.usdcAfterBob = usdc.balanceOf(address(bob));
        vars.daiAfterHook = dai.balanceOf(poolHooksContract);
        vars.usdcAfterHook = usdc.balanceOf(poolHooksContract);
        vars.daiAfterVault = dai.balanceOf(address(vault));
        vars.usdcAfterVault = usdc.balanceOf(address(vault));
        vars.poolBalancesAfter = vault.getRawBalances(pool);

        uint256 poolBalanceChange;

        if (isBeforeHook == true) {
            if (kind == SwapKind.EXACT_IN) {
                assertEq(vars.daiBeforeBob - vars.daiAfterBob, swapAmount, "Bob DAI balance is wrong");
                if (hookFee > 0) {
                    poolBalanceChange = swapAmount - hookFee;
                    assertEq(vars.usdcAfterHook - vars.usdcBeforeHook, 0, "Hook USDC balance is wrong");
                    assertEq(vars.usdcAfterBob - vars.usdcBeforeBob, poolBalanceChange, "Bob USDC balance is wrong");
                    assertEq(vars.daiAfterHook - vars.daiBeforeHook, hookFee, "Hook DAI balance is wrong");
                } else if (hookDiscount > 0) {
                    poolBalanceChange = swapAmount + hookDiscount;
                    assertEq(vars.usdcBeforeHook, vars.usdcAfterHook, "Hook USDC balance is wrong");
                    assertEq(vars.usdcAfterBob - vars.usdcBeforeBob, poolBalanceChange, "Bob USDC balance is wrong");
                    assertEq(vars.daiBeforeHook - vars.daiAfterHook, hookDiscount, "Hook DAI balance is wrong");
                }
            } else {
                assertEq(vars.usdcAfterBob - vars.usdcBeforeBob, swapAmount, "Bob USDC balance is wrong");
                if (hookFee > 0) {
                    poolBalanceChange = swapAmount + hookFee;
                    assertEq(vars.daiAfterHook, vars.daiBeforeHook, "Hook DAI balance is wrong");
                    assertEq(vars.daiBeforeBob - vars.daiAfterBob, poolBalanceChange, "Bob DAI balance is wrong");
                    assertEq(vars.usdcAfterHook - vars.usdcBeforeHook, hookFee, "Hook USDC balance is wrong");
                } else if (hookDiscount > 0) {
                    poolBalanceChange = swapAmount - hookDiscount;
                    assertEq(vars.daiBeforeHook, vars.daiAfterHook, "Hook DAI balance is wrong");
                    assertEq(vars.daiBeforeBob - vars.daiAfterBob, poolBalanceChange, "Bob DAI balance is wrong");
                    assertEq(vars.usdcBeforeHook - vars.usdcAfterHook, hookDiscount, "Hook USDC balance is wrong");
                }
            }
        } else if (isBeforeHook == false) {
            poolBalanceChange = swapAmount;
            if (kind == SwapKind.EXACT_IN) {
                assertEq(vars.daiBeforeBob - vars.daiAfterBob, swapAmount, "Bob DAI balance is wrong");
                if (hookFee > 0) {
                    assertEq(vars.daiAfterHook, vars.daiBeforeHook, "Hook DAI balance is wrong");
                    assertEq(vars.usdcAfterBob - vars.usdcBeforeBob, swapAmount - hookFee, "Bob USDC balance is wrong");
                    assertEq(vars.usdcAfterHook - vars.usdcBeforeHook, hookFee, "Hook USDC balance is wrong");
                } else if (hookDiscount > 0) {
                    assertEq(vars.daiBeforeHook, vars.daiAfterHook, "Hook DAI balance is wrong");
                    assertEq(
                        vars.usdcAfterBob - vars.usdcBeforeBob,
                        swapAmount + hookDiscount,
                        "Bob USDC balance is wrong"
                    );
                    assertEq(vars.usdcBeforeHook - vars.usdcAfterHook, hookDiscount, "Hook USDC balance is wrong");
                }
            } else {
                assertEq(vars.usdcAfterBob - vars.usdcBeforeBob, swapAmount, "Bob USDC balance is wrong");
                if (hookFee > 0) {
                    assertEq(vars.usdcAfterHook, vars.usdcBeforeHook, "Hook USDC balance is wrong");
                    assertEq(vars.daiBeforeBob - vars.daiAfterBob, swapAmount + hookFee, "Bob DAI balance is wrong");
                    assertEq(vars.daiAfterHook - vars.daiBeforeHook, hookFee, "Hook DAI balance is wrong");
                } else if (hookDiscount > 0) {
                    assertEq(vars.usdcBeforeHook, vars.usdcAfterHook, "Hook USDC balance is wrong");
                    assertEq(
                        vars.daiBeforeBob - vars.daiAfterBob,
                        swapAmount - hookDiscount,
                        "Bob DAI balance is wrong"
                    );
                    assertEq(vars.daiBeforeHook - vars.daiAfterHook, hookDiscount, "Hook DAI balance is wrong");
                }
            }
        }

        assertEq(
            vars.poolBalancesAfter[daiIdx] - vars.poolBalancesBefore[daiIdx],
            poolBalanceChange,
            "Pool DAI balance is wrong"
        );
        assertEq(
            vars.poolBalancesBefore[usdcIdx] - vars.poolBalancesAfter[usdcIdx],
            poolBalanceChange,
            "Pool USDC balance is wrong"
        );
        assertEq(vars.daiAfterVault - vars.daiBeforeVault, poolBalanceChange, "Vault DAI balance is wrong");
        assertEq(vars.usdcBeforeVault - vars.usdcAfterVault, poolBalanceChange, "Vault USDC balance is wrong");
    }
}
