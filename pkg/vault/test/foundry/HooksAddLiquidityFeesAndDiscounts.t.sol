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

        HookTestLocals memory vars = _createHookTestLocals();

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

        _checkOnBeforeAddLiquidityTestResults(vars, expectedAmountsIn, expectedBptOut, hookFee, 0);
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

        HookTestLocals memory vars = _createHookTestLocals();

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

        _checkOnBeforeAddLiquidityTestResults(vars, expectedAmountsIn, expectedBptOut, 0, hookDiscount);
    }

    function testOnAfterAddLiquidityHookFeeExactIn() public {
        HooksConfig memory hooksConfig = vault.getHooksConfig(address(pool));
        hooksConfig.shouldCallAfterAddLiquidity = true;
        vault.setHooksConfig(address(pool), hooksConfig);

        uint256[] memory amountsInPoolBalance = [_swapAmount, _swapAmount].toMemoryArray();
        uint256 expectedBptOut = amountsInPoolBalance[daiIdx] + amountsInPoolBalance[usdcIdx];
        uint256[] memory expectedBalances = [poolInitAmount, poolInitAmount].toMemoryArray();
        expectedBalances[daiIdx] += amountsInPoolBalance[daiIdx];
        expectedBalances[usdcIdx] += amountsInPoolBalance[usdcIdx];

        uint256 hookFee = 1e3;
        PoolHooksMock(poolHooksContract).setOnAfterAddLiquidityHookFee(hookFee);
        uint256[] memory maxAmountsIn = [_swapAmount + hookFee, _swapAmount + hookFee].toMemoryArray();

        HookTestLocals memory vars = _createHookTestLocals();

        // Check that the swap gets updated balances that reflect the updated balance in the before hook
        vm.prank(bob);
        // Check if balances were not changed before onBeforeHook
        vm.expectCall(
            address(poolHooksContract),
            abi.encodeWithSelector(
                IHooks.onAfterAddLiquidity.selector,
                address(router),
                pool,
                amountsInPoolBalance,
                amountsInPoolBalance,
                expectedBptOut,
                expectedBalances,
                bytes("")
            )
        );

        router.addLiquidityProportional(pool, maxAmountsIn, expectedBptOut, false, bytes(""));

        _checkOnAfterAddLiquidityTestResults(vars, amountsInPoolBalance, expectedBptOut, hookFee, 0);
    }

    function testOnAfterAddLiquidityHookDiscountExactIn() public {
        HooksConfig memory hooksConfig = vault.getHooksConfig(address(pool));
        hooksConfig.shouldCallAfterAddLiquidity = true;
        vault.setHooksConfig(address(pool), hooksConfig);

        uint256[] memory amountsInPoolBalance = [_swapAmount, _swapAmount].toMemoryArray();
        uint256 expectedBptOut = amountsInPoolBalance[daiIdx] + amountsInPoolBalance[usdcIdx];
        uint256[] memory expectedBalances = [poolInitAmount, poolInitAmount].toMemoryArray();
        expectedBalances[daiIdx] += amountsInPoolBalance[daiIdx];
        expectedBalances[usdcIdx] += amountsInPoolBalance[usdcIdx];

        uint256 hookDiscount = 1e3;
        PoolHooksMock(poolHooksContract).setOnAfterAddLiquidityHookDiscount(hookDiscount);

        // Mint tokens so that hook can pay for the discount
        dai.mint(poolHooksContract, hookDiscount);
        usdc.mint(poolHooksContract, hookDiscount);

        HookTestLocals memory vars = _createHookTestLocals();

        // Check that the swap gets updated balances that reflect the updated balance in the before hook
        vm.prank(bob);
        // Check if balances were not changed before onBeforeHook
        vm.expectCall(
            address(poolHooksContract),
            abi.encodeWithSelector(
                IHooks.onAfterAddLiquidity.selector,
                address(router),
                pool,
                amountsInPoolBalance,
                amountsInPoolBalance,
                expectedBptOut,
                expectedBalances,
                bytes("")
            )
        );

        router.addLiquidityProportional(pool, amountsInPoolBalance, expectedBptOut, false, bytes(""));

        _checkOnAfterAddLiquidityTestResults(vars, amountsInPoolBalance, expectedBptOut, 0, hookDiscount);
    }

    struct WalletState {
        uint256 daiBefore;
        uint256 daiAfter;
        uint256 usdcBefore;
        uint256 usdcAfter;
        uint256 bptBefore;
        uint256 bptAfter;
    }

    struct HookTestLocals {
        WalletState bob;
        WalletState hook;
        WalletState vault;
        uint256[] poolBefore;
        uint256[] poolAfter;
        uint256 bptSupplyBefore;
        uint256 bptSupplyAfter;
    }

    function _createHookTestLocals() private returns (HookTestLocals memory vars) {
        vars.bob.daiBefore = dai.balanceOf(address(bob));
        vars.bob.usdcBefore = usdc.balanceOf(address(bob));
        vars.bob.bptBefore = IERC20(pool).balanceOf(address(bob));
        vars.hook.daiBefore = dai.balanceOf(address(poolHooksContract));
        vars.hook.usdcBefore = usdc.balanceOf(address(poolHooksContract));
        vars.vault.daiBefore = dai.balanceOf(address(vault));
        vars.vault.usdcBefore = usdc.balanceOf(address(vault));
        vars.poolBefore = vault.getRawBalances(pool);
        vars.bptSupplyBefore = BalancerPoolToken(pool).totalSupply();
    }

    function _fillAfterHookTestLocals(HookTestLocals memory vars) private {
        vars.bob.daiAfter = dai.balanceOf(address(bob));
        vars.bob.usdcAfter = usdc.balanceOf(address(bob));
        vars.bob.bptAfter = IERC20(pool).balanceOf(address(bob));
        vars.hook.daiAfter = dai.balanceOf(address(poolHooksContract));
        vars.hook.usdcAfter = usdc.balanceOf(address(poolHooksContract));
        vars.vault.daiAfter = dai.balanceOf(address(vault));
        vars.vault.usdcAfter = usdc.balanceOf(address(vault));
        vars.poolAfter = vault.getRawBalances(pool);
        vars.bptSupplyAfter = BalancerPoolToken(pool).totalSupply();
    }

    function _checkOnBeforeAddLiquidityTestResults(
        HookTestLocals memory vars,
        uint256[] memory expectedAmountsIn,
        uint256 expectedBptOut,
        uint256 expectedHookFee,
        uint256 expectedHookDiscount
    ) private {
        _fillAfterHookTestLocals(vars);

        assertEq(vars.bob.daiBefore - vars.bob.daiAfter, expectedAmountsIn[daiIdx], "Bob DAI balance is wrong");
        assertEq(vars.bob.usdcBefore - vars.bob.usdcAfter, expectedAmountsIn[usdcIdx], "Bob USDC balance is wrong");
        assertEq(vars.bob.bptAfter - vars.bob.bptBefore, expectedBptOut, "Bob BPT balance is wrong");

        if (expectedHookFee > 0) {
            assertEq(vars.hook.daiAfter - vars.hook.daiBefore, expectedHookFee, "Hook DAI balance is wrong");
            assertEq(vars.hook.usdcAfter - vars.hook.usdcBefore, expectedHookFee, "Hook USDC balance is wrong");
            _checkPoolAndVaultBalances(
                vars,
                expectedAmountsIn[daiIdx] - expectedHookFee,
                expectedAmountsIn[usdcIdx] - expectedHookFee,
                expectedBptOut
            );
        } else if (expectedHookDiscount > 0) {
            assertEq(vars.hook.daiBefore - vars.hook.daiAfter, expectedHookDiscount, "Hook DAI balance is wrong");
            assertEq(vars.hook.usdcBefore - vars.hook.usdcAfter, expectedHookDiscount, "Hook USDC balance is wrong");
            _checkPoolAndVaultBalances(
                vars,
                expectedAmountsIn[daiIdx] + expectedHookDiscount,
                expectedAmountsIn[usdcIdx] + expectedHookDiscount,
                expectedBptOut
            );
        }
    }

    function _checkOnAfterAddLiquidityTestResults(
        HookTestLocals memory vars,
        uint256[] memory expectedAmountsIn,
        uint256 expectedBptOut,
        uint256 expectedHookFee,
        uint256 expectedHookDiscount
    ) private {
        _fillAfterHookTestLocals(vars);

        assertEq(vars.bob.bptAfter - vars.bob.bptBefore, expectedBptOut, "Bob BPT balance is wrong");
        _checkPoolAndVaultBalances(vars, expectedAmountsIn[daiIdx], expectedAmountsIn[usdcIdx], expectedBptOut);

        if (expectedHookFee > 0) {
            assertEq(
                vars.bob.daiBefore - vars.bob.daiAfter,
                expectedAmountsIn[daiIdx] + expectedHookFee,
                "Bob DAI balance is wrong"
            );
            assertEq(
                vars.bob.usdcBefore - vars.bob.usdcAfter,
                expectedAmountsIn[usdcIdx] + expectedHookFee,
                "Bob USDC balance is wrong"
            );

            assertEq(vars.hook.daiAfter - vars.hook.daiBefore, expectedHookFee, "Hook DAI balance is wrong");
            assertEq(vars.hook.usdcAfter - vars.hook.usdcBefore, expectedHookFee, "Hook USDC balance is wrong");
        } else if (expectedHookDiscount > 0) {
            assertEq(
                vars.bob.daiBefore - vars.bob.daiAfter,
                expectedAmountsIn[daiIdx] - expectedHookDiscount,
                "Bob DAI balance is wrong"
            );
            assertEq(
                vars.bob.usdcBefore - vars.bob.usdcAfter,
                expectedAmountsIn[usdcIdx] - expectedHookDiscount,
                "Bob USDC balance is wrong"
            );

            assertEq(vars.hook.daiBefore - vars.hook.daiAfter, expectedHookDiscount, "Hook DAI balance is wrong");
            assertEq(vars.hook.usdcBefore - vars.hook.usdcAfter, expectedHookDiscount, "Hook USDC balance is wrong");
        }
    }

    function _checkPoolAndVaultBalances(
        HookTestLocals memory vars,
        uint256 expectedDeltaDai,
        uint256 expectedDeltaUsdc,
        uint256 expectedBptOut
    ) private {
        assertEq(vars.poolAfter[daiIdx] - vars.poolBefore[daiIdx], expectedDeltaDai, "Pool DAI balance is wrong");
        assertEq(vars.poolAfter[usdcIdx] - vars.poolBefore[usdcIdx], expectedDeltaUsdc, "Pool USDC balance is wrong");
        assertEq(vars.bptSupplyAfter - vars.bptSupplyBefore, expectedBptOut, "Pool Supply is wrong");

        assertEq(vars.vault.daiAfter - vars.vault.daiBefore, expectedDeltaDai, "Vault DAI balance is wrong");
        assertEq(vars.vault.usdcAfter - vars.vault.usdcBefore, expectedDeltaUsdc, "Vault USDC balance is wrong");
    }
}
