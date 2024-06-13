// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import {
    AddLiquidityKind,
    RemoveLiquidityKind,
    SwapKind
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { BasePoolMath } from "@balancer-labs/v3-solidity-utils/contracts/math/BasePoolMath.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";
import { BalancerPoolToken } from "@balancer-labs/v3-vault/contracts/BalancerPoolToken.sol";

import { FeeTakingHook } from "../../contracts/FeeTakingHook.sol";

contract FeeTakingHookTest is BaseVaultTest {
    using FixedPoint for uint256;
    using ArrayHelpers for *;

    uint256 internal daiIdx;
    uint256 internal usdcIdx;

    uint256 private constant _minSwapAmount = 1e6;
    uint256 private constant _minBptOut = 1e6;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));
    }

    // Sets the hook of the pool and stores the address in the variable poolHooksContract
    function createHook() internal override returns (address) {
        FeeTakingHook hook = new FeeTakingHook(IVault(address(vault)));
        return address(hook);
    }

    function testFeeSwapExactIn__Fuzz(uint256 swapAmount, uint256 hookFeePercentage) public {
        // Swap between _minSwapAmount and whole pool liquidity (pool math is linear)
        swapAmount = bound(swapAmount, _minSwapAmount, poolInitAmount);

        // Fee between 0 and 100%
        hookFeePercentage = bound(hookFeePercentage, 0, 1e18);
        FeeTakingHook(poolHooksContract).setHookSwapFeePercentage(hookFeePercentage);
        uint256 hookFee = swapAmount.mulDown(hookFeePercentage);

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
                    amountInScaled18: swapAmount,
                    amountOutScaled18: swapAmount,
                    tokenInBalanceScaled18: poolInitAmount + swapAmount,
                    tokenOutBalanceScaled18: poolInitAmount - swapAmount,
                    amountCalculatedScaled18: swapAmount,
                    amountCalculatedRaw: swapAmount,
                    router: address(router),
                    pool: pool,
                    userData: ""
                })
            )
        );

        router.swapSingleTokenExactIn(address(pool), dai, usdc, swapAmount, 0, MAX_UINT256, false, bytes(""));

        _fillAfterHookTestLocals(vars);

        assertEq(vars.bob.daiBefore - vars.bob.daiAfter, swapAmount, "Bob DAI balance is wrong");
        assertEq(vars.hook.daiBefore, vars.hook.daiAfter, "Hook DAI balance is wrong");
        assertEq(vars.bob.usdcAfter - vars.bob.usdcBefore, swapAmount - hookFee, "Bob USDC balance is wrong");
        assertEq(vars.hook.usdcAfter - vars.hook.usdcBefore, hookFee, "Hook USDC balance is wrong");

        _checkPoolAndVaultBalancesAfterSwap(vars, swapAmount);
    }

    function testFeeSwapExactOut__Fuzz(uint256 swapAmount, uint256 hookFeePercentage) public {
        // Swap between _minSwapAmount and whole pool liquidity (pool math is linear)
        swapAmount = bound(swapAmount, _minSwapAmount, poolInitAmount);

        // Fee between 0 and 100%
        hookFeePercentage = bound(hookFeePercentage, 0, 1e18);
        FeeTakingHook(poolHooksContract).setHookSwapFeePercentage(hookFeePercentage);
        uint256 hookFee = swapAmount.mulDown(hookFeePercentage);

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
                    amountInScaled18: swapAmount,
                    amountOutScaled18: swapAmount,
                    tokenInBalanceScaled18: poolInitAmount + swapAmount,
                    tokenOutBalanceScaled18: poolInitAmount - swapAmount,
                    amountCalculatedScaled18: swapAmount,
                    amountCalculatedRaw: swapAmount,
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
            swapAmount,
            MAX_UINT256,
            MAX_UINT256,
            false,
            bytes("")
        );

        _fillAfterHookTestLocals(vars);

        assertEq(vars.bob.usdcAfter - vars.bob.usdcBefore, swapAmount, "Bob USDC balance is wrong");
        assertEq(vars.hook.usdcBefore, vars.hook.usdcAfter, "Hook USDC balance is wrong");
        assertEq(vars.bob.daiBefore - vars.bob.daiAfter, swapAmount + hookFee, "Bob DAI balance is wrong");
        assertEq(vars.hook.daiAfter - vars.hook.daiBefore, hookFee, "Hook DAI balance is wrong");

        _checkPoolAndVaultBalancesAfterSwap(vars, swapAmount);
    }

    function testHookFeeAddLiquidityExactIn__Fuzz(uint256 expectedBptOut, uint256 hookFeePercentage) public {
        // Add fee between 0 and 100%
        hookFeePercentage = bound(hookFeePercentage, 0, 1e18);
        FeeTakingHook(poolHooksContract).setAddLiquidityHookFeePercentage(hookFeePercentage);

        // Since operation is not settled in advance, max expected bpt out can't generate a hook fee higher than
        // pool liquidity, or else the hook won't be able to charge fees
        expectedBptOut = bound(
            expectedBptOut,
            _minBptOut,
            hookFeePercentage == 0 ? MAX_UINT256 : poolInitAmount.divDown(hookFeePercentage)
        );

        // Make sure bob has enough to pay for the transaction
        if (expectedBptOut > dai.balanceOf(bob)) {
            expectedBptOut = dai.balanceOf(bob);
        }

        uint256[] memory actualAmountsIn = BasePoolMath.computeProportionalAmountsIn(
            [poolInitAmount, poolInitAmount].toMemoryArray(),
            BalancerPoolToken(pool).totalSupply(),
            expectedBptOut
        );
        uint256 actualAmountIn = actualAmountsIn[0];
        uint256 hookFee = actualAmountIn.mulDown(hookFeePercentage);

        uint256[] memory expectedBalances = [poolInitAmount + actualAmountIn, poolInitAmount + actualAmountIn]
            .toMemoryArray();

        HookTestLocals memory vars = _createHookTestLocals();

        vm.prank(bob);
        vm.expectCall(
            address(poolHooksContract),
            abi.encodeWithSelector(
                IHooks.onAfterAddLiquidity.selector,
                address(router),
                pool,
                AddLiquidityKind.PROPORTIONAL,
                actualAmountsIn,
                actualAmountsIn,
                expectedBptOut,
                expectedBalances,
                bytes("")
            )
        );

        uint256[] memory maxAmountsIn = [actualAmountIn + hookFee, actualAmountIn + hookFee].toMemoryArray();
        router.addLiquidityProportional(pool, maxAmountsIn, expectedBptOut, false, bytes(""));

        _checkAddLiquidityHookTestResults(vars, actualAmountsIn, expectedBptOut, hookFee, 0);
    }

    function testHookFeeRemoveLiquidityExactIn__Fuzz(uint256 expectedBptIn, uint256 hookFeePercentage) public {
        // Add liquidity so bob has BPT to remove liquidity
        vm.prank(bob);
        router.addLiquidityUnbalanced(
            pool,
            [poolInitAmount, poolInitAmount].toMemoryArray(),
            poolInitAmount,
            false,
            bytes("")
        );

        // Add fee between 0 and 100%
        hookFeePercentage = bound(hookFeePercentage, 0, 1e18);
        FeeTakingHook(poolHooksContract).setRemoveLiquidityHookFeePercentage(hookFeePercentage);

        // Make sure bob has enough to pay for the transaction
        expectedBptIn = bound(expectedBptIn, _minBptOut, BalancerPoolToken(pool).balanceOf(bob));

        // Since bob added poolInitAmount in each token of the pool, the pool balances are doubled
        uint256[] memory actualAmountsOut = BasePoolMath.computeProportionalAmountsOut(
            [2 * poolInitAmount, 2 * poolInitAmount].toMemoryArray(),
            BalancerPoolToken(pool).totalSupply(),
            expectedBptIn
        );
        uint256 actualAmountOut = actualAmountsOut[0];
        uint256 hookFee = actualAmountOut.mulDown(hookFeePercentage);

        uint256[] memory expectedBalances = [2 * poolInitAmount - actualAmountOut, 2 * poolInitAmount - actualAmountOut]
            .toMemoryArray();

        HookTestLocals memory vars = _createHookTestLocals();

        vm.prank(bob);
        vm.expectCall(
            address(poolHooksContract),
            abi.encodeWithSelector(
                IHooks.onAfterRemoveLiquidity.selector,
                address(router),
                pool,
                RemoveLiquidityKind.PROPORTIONAL,
                expectedBptIn,
                actualAmountsOut,
                actualAmountsOut,
                expectedBalances,
                bytes("")
            )
        );

        uint256[] memory minAmountsOut = [actualAmountOut - hookFee, actualAmountOut - hookFee].toMemoryArray();
        router.removeLiquidityProportional(pool, expectedBptIn, minAmountsOut, false, bytes(""));

        _checkRemoveLiquidityHookTestResults(vars, actualAmountsOut, expectedBptIn, hookFee, 0);
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

    function _checkPoolAndVaultBalancesAfterSwap(HookTestLocals memory vars, uint256 poolBalanceChange) private {
        // Considers swap fee = 0, so only hook fees were charged
        assertEq(vars.poolAfter[daiIdx] - vars.poolBefore[daiIdx], poolBalanceChange, "Pool DAI balance is wrong");
        assertEq(vars.poolBefore[usdcIdx] - vars.poolAfter[usdcIdx], poolBalanceChange, "Pool USDC balance is wrong");
        assertEq(vars.vault.daiAfter - vars.vault.daiBefore, poolBalanceChange, "Vault DAI balance is wrong");
        assertEq(vars.vault.usdcBefore - vars.vault.usdcAfter, poolBalanceChange, "Vault USDC balance is wrong");
    }

    function _checkAddLiquidityHookTestResults(
        HookTestLocals memory vars,
        uint256[] memory actualAmountsIn,
        uint256 expectedBptOut,
        uint256 expectedHookFee,
        uint256 expectedHookDiscount
    ) private {
        _fillAfterHookTestLocals(vars);

        assertEq(vars.bob.bptAfter - vars.bob.bptBefore, expectedBptOut, "Bob BPT balance is wrong");

        assertEq(
            vars.poolAfter[daiIdx] - vars.poolBefore[daiIdx],
            actualAmountsIn[daiIdx],
            "Pool DAI balance is wrong"
        );
        assertEq(
            vars.poolAfter[usdcIdx] - vars.poolBefore[usdcIdx],
            actualAmountsIn[usdcIdx],
            "Pool USDC balance is wrong"
        );
        assertEq(vars.bptSupplyAfter - vars.bptSupplyBefore, expectedBptOut, "Pool Supply is wrong");

        assertEq(vars.vault.daiAfter - vars.vault.daiBefore, actualAmountsIn[daiIdx], "Vault DAI balance is wrong");
        assertEq(vars.vault.usdcAfter - vars.vault.usdcBefore, actualAmountsIn[usdcIdx], "Vault USDC balance is wrong");

        if (expectedHookFee > 0) {
            assertEq(
                vars.bob.daiBefore - vars.bob.daiAfter,
                actualAmountsIn[daiIdx] + expectedHookFee,
                "Bob DAI balance is wrong"
            );
            assertEq(
                vars.bob.usdcBefore - vars.bob.usdcAfter,
                actualAmountsIn[usdcIdx] + expectedHookFee,
                "Bob USDC balance is wrong"
            );

            assertEq(vars.hook.daiAfter - vars.hook.daiBefore, expectedHookFee, "Hook DAI balance is wrong");
            assertEq(vars.hook.usdcAfter - vars.hook.usdcBefore, expectedHookFee, "Hook USDC balance is wrong");
        } else if (expectedHookDiscount > 0) {
            assertEq(
                vars.bob.daiBefore - vars.bob.daiAfter,
                actualAmountsIn[daiIdx] - expectedHookDiscount,
                "Bob DAI balance is wrong"
            );
            assertEq(
                vars.bob.usdcBefore - vars.bob.usdcAfter,
                actualAmountsIn[usdcIdx] - expectedHookDiscount,
                "Bob USDC balance is wrong"
            );

            assertEq(vars.hook.daiBefore - vars.hook.daiAfter, expectedHookDiscount, "Hook DAI balance is wrong");
            assertEq(vars.hook.usdcBefore - vars.hook.usdcAfter, expectedHookDiscount, "Hook USDC balance is wrong");
        }
    }

    function _checkRemoveLiquidityHookTestResults(
        HookTestLocals memory vars,
        uint256[] memory actualAmountsOut,
        uint256 expectedBptIn,
        uint256 expectedHookFee,
        uint256 expectedHookDiscount
    ) private {
        _fillAfterHookTestLocals(vars);

        assertEq(vars.bob.bptBefore - vars.bob.bptAfter, expectedBptIn, "Bob BPT balance is wrong");

        assertEq(
            vars.poolBefore[daiIdx] - vars.poolAfter[daiIdx],
            actualAmountsOut[daiIdx],
            "Pool DAI balance is wrong"
        );
        assertEq(
            vars.poolBefore[usdcIdx] - vars.poolAfter[usdcIdx],
            actualAmountsOut[usdcIdx],
            "Pool USDC balance is wrong"
        );
        assertEq(vars.bptSupplyBefore - vars.bptSupplyAfter, expectedBptIn, "Pool Supply is wrong");

        assertEq(vars.vault.daiBefore - vars.vault.daiAfter, actualAmountsOut[daiIdx], "Vault DAI balance is wrong");
        assertEq(
            vars.vault.usdcBefore - vars.vault.usdcAfter,
            actualAmountsOut[usdcIdx],
            "Vault USDC balance is wrong"
        );

        if (expectedHookFee > 0) {
            assertEq(
                vars.bob.daiAfter - vars.bob.daiBefore,
                actualAmountsOut[daiIdx] - expectedHookFee,
                "Bob DAI balance is wrong"
            );
            assertEq(
                vars.bob.usdcAfter - vars.bob.usdcBefore,
                actualAmountsOut[usdcIdx] - expectedHookFee,
                "Bob USDC balance is wrong"
            );

            assertEq(vars.hook.daiAfter - vars.hook.daiBefore, expectedHookFee, "Hook DAI balance is wrong");
            assertEq(vars.hook.usdcAfter - vars.hook.usdcBefore, expectedHookFee, "Hook USDC balance is wrong");
        } else if (expectedHookDiscount > 0) {
            assertEq(
                vars.bob.daiAfter - vars.bob.daiBefore,
                actualAmountsOut[daiIdx] + expectedHookDiscount,
                "Bob DAI balance is wrong"
            );
            assertEq(
                vars.bob.usdcAfter - vars.bob.usdcBefore,
                actualAmountsOut[usdcIdx] + expectedHookDiscount,
                "Bob USDC balance is wrong"
            );

            assertEq(vars.hook.daiBefore - vars.hook.daiAfter, expectedHookDiscount, "Hook DAI balance is wrong");
            assertEq(vars.hook.usdcBefore - vars.hook.usdcAfter, expectedHookDiscount, "Hook USDC balance is wrong");
        }
    }

    function _createHookTestLocals() private returns (HookTestLocals memory vars) {
        vars.bob.daiBefore = dai.balanceOf(address(bob));
        vars.bob.usdcBefore = usdc.balanceOf(address(bob));
        vars.bob.bptBefore = BalancerPoolToken(pool).balanceOf(address(bob));
        vars.hook.daiBefore = dai.balanceOf(poolHooksContract);
        vars.hook.usdcBefore = usdc.balanceOf(poolHooksContract);
        vars.vault.daiBefore = dai.balanceOf(address(vault));
        vars.vault.usdcBefore = usdc.balanceOf(address(vault));
        vars.poolBefore = vault.getRawBalances(pool);
        vars.bptSupplyBefore = BalancerPoolToken(pool).totalSupply();
    }

    function _fillAfterHookTestLocals(HookTestLocals memory vars) private {
        vars.bob.daiAfter = dai.balanceOf(address(bob));
        vars.bob.usdcAfter = usdc.balanceOf(address(bob));
        vars.bob.bptAfter = BalancerPoolToken(pool).balanceOf(address(bob));
        vars.hook.daiAfter = dai.balanceOf(poolHooksContract);
        vars.hook.usdcAfter = usdc.balanceOf(poolHooksContract);
        vars.vault.daiAfter = dai.balanceOf(address(vault));
        vars.vault.usdcAfter = usdc.balanceOf(address(vault));
        vars.poolAfter = vault.getRawBalances(pool);
        vars.bptSupplyAfter = BalancerPoolToken(pool).totalSupply();
    }
}
