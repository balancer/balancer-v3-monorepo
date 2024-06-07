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

        uint256[] memory expectedAmountsIn = [_swapAmount, _swapAmount].toMemoryArray();
        uint256 expectedBptOut = expectedAmountsIn[daiIdx] + expectedAmountsIn[usdcIdx];
        uint256[] memory expectedBalances = [poolInitAmount, poolInitAmount].toMemoryArray();
        expectedBalances[daiIdx] += expectedAmountsIn[daiIdx];
        expectedBalances[usdcIdx] += expectedAmountsIn[usdcIdx];

        uint256 hookFee = 1e3;
        PoolHooksMock(poolHooksContract).setOnAfterAddLiquidityHookFee(hookFee);

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
                expectedAmountsIn,
                expectedAmountsIn,
                expectedBptOut,
                expectedBalances,
                bytes("")
            )
        );

        router.addLiquidityUnbalanced(pool, expectedAmountsIn, _swapAmount, false, bytes(""));

        _checkOnAfterAddLiquidityTestResults(vars, expectedAmountsIn, expectedBptOut, hookFee, 0);
    }

    function testOnAfterAddLiquidityHookDiscountExactIn() public {
        HooksConfig memory hooksConfig = vault.getHooksConfig(address(pool));
        hooksConfig.shouldCallAfterAddLiquidity = true;
        vault.setHooksConfig(address(pool), hooksConfig);

        uint256[] memory expectedAmountsIn = [_swapAmount, _swapAmount].toMemoryArray();
        uint256 expectedBptOut = expectedAmountsIn[daiIdx] + expectedAmountsIn[usdcIdx];
        uint256[] memory expectedBalances = [poolInitAmount, poolInitAmount].toMemoryArray();
        expectedBalances[daiIdx] += expectedAmountsIn[daiIdx];
        expectedBalances[usdcIdx] += expectedAmountsIn[usdcIdx];

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
                expectedAmountsIn,
                expectedAmountsIn,
                expectedBptOut,
                expectedBalances,
                bytes("")
            )
        );

        router.addLiquidityUnbalanced(pool, expectedAmountsIn, _swapAmount, false, bytes(""));

        _checkOnAfterAddLiquidityTestResults(vars, expectedAmountsIn, expectedBptOut, 0, hookDiscount);
    }

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

    function _createHookTestLocals() private returns (HookTestLocals memory vars) {
        vars.daiBeforeBob = dai.balanceOf(address(bob));
        vars.usdcBeforeBob = usdc.balanceOf(address(bob));
        vars.bptBeforeBob = IERC20(pool).balanceOf(address(bob));
        vars.daiBeforeHook = dai.balanceOf(address(poolHooksContract));
        vars.usdcBeforeHook = usdc.balanceOf(address(poolHooksContract));
        vars.poolBalancesBeforeHook = vault.getRawBalances(pool);
        vars.poolSupplyBeforeHook = BalancerPoolToken(pool).totalSupply();
    }

    function _fillAfterHookTestLocals(HookTestLocals memory vars) private {
        vars.daiAfterBob = dai.balanceOf(address(bob));
        vars.usdcAfterBob = usdc.balanceOf(address(bob));
        vars.bptAfterBob = IERC20(pool).balanceOf(address(bob));
        vars.daiAfterHook = dai.balanceOf(address(poolHooksContract));
        vars.usdcAfterHook = usdc.balanceOf(address(poolHooksContract));
        vars.poolBalancesAfterHook = vault.getRawBalances(pool);
        vars.poolSupplyAfterHook = BalancerPoolToken(pool).totalSupply();
    }

    function _checkOnBeforeAddLiquidityTestResults(
        HookTestLocals memory vars,
        uint256[] memory expectedAmountsIn,
        uint256 expectedBptOut,
        uint256 expectedHookFee,
        uint256 expectedHookDiscount
    ) private {
        _fillAfterHookTestLocals(vars);

        assertEq(vars.daiBeforeBob - vars.daiAfterBob, expectedAmountsIn[daiIdx], "Bob DAI balance is wrong");
        assertEq(vars.usdcBeforeBob - vars.usdcAfterBob, expectedAmountsIn[usdcIdx], "Bob USDC balance is wrong");
        assertEq(vars.bptAfterBob - vars.bptBeforeBob, expectedBptOut, "Bob BPT balance is wrong");

        assertEq(vars.poolSupplyAfterHook - vars.poolSupplyBeforeHook, expectedBptOut, "Pool Supply is wrong");

        if (expectedHookFee > 0) {
            assertEq(vars.daiAfterHook - vars.daiBeforeHook, expectedHookFee, "Hook DAI balance is wrong");
            assertEq(vars.usdcAfterHook - vars.usdcBeforeHook, expectedHookFee, "Hook USDC balance is wrong");
            assertEq(
                vars.poolBalancesAfterHook[daiIdx] - vars.poolBalancesBeforeHook[daiIdx],
                expectedAmountsIn[daiIdx] - expectedHookFee,
                "Pool DAI balance is wrong"
            );
            assertEq(
                vars.poolBalancesAfterHook[usdcIdx] - vars.poolBalancesBeforeHook[usdcIdx],
                expectedAmountsIn[usdcIdx] - expectedHookFee,
                "Pool USDC balance is wrong"
            );
        } else if (expectedHookDiscount > 0) {
            assertEq(vars.daiBeforeHook - vars.daiAfterHook, expectedHookDiscount, "Hook DAI balance is wrong");
            assertEq(vars.usdcBeforeHook - vars.usdcAfterHook, expectedHookDiscount, "Hook USDC balance is wrong");
            assertEq(
                vars.poolBalancesAfterHook[daiIdx] - vars.poolBalancesBeforeHook[daiIdx],
                expectedAmountsIn[daiIdx] + expectedHookDiscount,
                "Pool DAI balance is wrong"
            );
            assertEq(
                vars.poolBalancesAfterHook[usdcIdx] - vars.poolBalancesBeforeHook[usdcIdx],
                expectedAmountsIn[usdcIdx] + expectedHookDiscount,
                "Pool USDC balance is wrong"
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

        assertEq(vars.bptAfterBob - vars.bptBeforeBob, expectedBptOut, "Bob BPT balance is wrong");
        assertEq(
            vars.poolBalancesAfterHook[daiIdx] - vars.poolBalancesBeforeHook[daiIdx],
            expectedAmountsIn[daiIdx],
            "Pool DAI balance is wrong"
        );
        assertEq(
            vars.poolBalancesAfterHook[usdcIdx] - vars.poolBalancesBeforeHook[usdcIdx],
            expectedAmountsIn[usdcIdx],
            "Pool USDC balance is wrong"
        );
        assertEq(vars.poolSupplyAfterHook - vars.poolSupplyBeforeHook, expectedBptOut, "Pool Supply is wrong");

        if (expectedHookFee > 0) {
            assertEq(
                vars.daiBeforeBob - vars.daiAfterBob,
                expectedAmountsIn[daiIdx] + expectedHookFee,
                "Bob DAI balance is wrong"
            );
            assertEq(
                vars.usdcBeforeBob - vars.usdcAfterBob,
                expectedAmountsIn[usdcIdx] + expectedHookFee,
                "Bob USDC balance is wrong"
            );

            assertEq(vars.daiAfterHook - vars.daiBeforeHook, expectedHookFee, "Hook DAI balance is wrong");
            assertEq(vars.usdcAfterHook - vars.usdcBeforeHook, expectedHookFee, "Hook USDC balance is wrong");
        } else if (expectedHookDiscount > 0) {
            assertEq(
                vars.daiBeforeBob - vars.daiAfterBob,
                expectedAmountsIn[daiIdx] - expectedHookDiscount,
                "Bob DAI balance is wrong"
            );
            assertEq(
                vars.usdcBeforeBob - vars.usdcAfterBob,
                expectedAmountsIn[usdcIdx] - expectedHookDiscount,
                "Bob USDC balance is wrong"
            );

            assertEq(vars.daiBeforeHook - vars.daiAfterHook, expectedHookDiscount, "Hook DAI balance is wrong");
            assertEq(vars.usdcBeforeHook - vars.usdcAfterHook, expectedHookDiscount, "Hook USDC balance is wrong");
        }
    }
}
