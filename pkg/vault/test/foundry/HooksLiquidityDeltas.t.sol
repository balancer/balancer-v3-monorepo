// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { BasePoolMath } from "@balancer-labs/v3-solidity-utils/contracts/math/BasePoolMath.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { BalancerPoolToken } from "../../contracts/BalancerPoolToken.sol";
import { PoolHooksMock } from "../../contracts/test/PoolHooksMock.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract HooksLiquidityDeltasTest is BaseVaultTest {
    using FixedPoint for uint256;
    using ArrayHelpers for *;

    uint256 internal daiIdx;
    uint256 internal usdcIdx;

    uint256 private _swapAmount;
    uint256 private constant _minBptOut = 1e6;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        _swapAmount = poolInitAmount / 100;

        // Sets the pool address in the hook, so we can check balances of the pool inside the hook
        PoolHooksMock(poolHooksContract).setPool(address(pool));

        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));
    }

    function createHook() internal override returns (address) {
        IHooks.HookFlags memory hookFlags;
        hookFlags.shouldCallAfterAddLiquidity = true;
        hookFlags.shouldCallAfterRemoveLiquidity = true;
        return _createHook(hookFlags);
    }

    function testHookFeeAddLiquidityExactIn_Fuzz(uint256 expectedBptOut, uint256 hookFeePercentage) public {
        // Add fee between 0 and 100%
        hookFeePercentage = bound(hookFeePercentage, 0, 1e18);
        PoolHooksMock(poolHooksContract).setAddLiquidityHookFeePercentage(hookFeePercentage);

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

    function testHookDiscountAddLiquidityExactIn_Fuzz(uint256 expectedBptOut, uint256 hookDiscountPercentage) public {
        // Add discount between 0 and 100%
        hookDiscountPercentage = bound(hookDiscountPercentage, 0, 1e18);
        PoolHooksMock(poolHooksContract).setAddLiquidityHookDiscountPercentage(hookDiscountPercentage);

        // Make sure bob has enough to pay for the transaction
        expectedBptOut = bound(expectedBptOut, _minBptOut, dai.balanceOf(bob));

        uint256[] memory actualAmountsIn = BasePoolMath.computeProportionalAmountsIn(
            [poolInitAmount, poolInitAmount].toMemoryArray(),
            BalancerPoolToken(pool).totalSupply(),
            expectedBptOut
        );
        uint256 actualAmountIn = actualAmountsIn[0];
        uint256 hookDiscount = actualAmountIn.mulDown(hookDiscountPercentage);

        // Hook needs to have tokens to pay for discount, else balances do not settle
        dai.mint(poolHooksContract, hookDiscount);
        usdc.mint(poolHooksContract, hookDiscount);

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
                actualAmountsIn,
                actualAmountsIn,
                expectedBptOut,
                expectedBalances,
                bytes("")
            )
        );

        router.addLiquidityProportional(pool, actualAmountsIn, expectedBptOut, false, bytes(""));

        _checkAddLiquidityHookTestResults(vars, actualAmountsIn, expectedBptOut, 0, hookDiscount);
    }

    function testHookFeeRemoveLiquidityExactIn_Fuzz(uint256 expectedBptIn, uint256 hookFeePercentage) public {
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
        PoolHooksMock(poolHooksContract).setRemoveLiquidityHookFeePercentage(hookFeePercentage);

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

    function testHookDiscountRemoveLiquidityExactIn_Fuzz(uint256 expectedBptIn, uint256 hookDiscountPercentage) public {
        // Add liquidity so bob has BPT to remove liquidity
        vm.prank(bob);
        router.addLiquidityUnbalanced(
            pool,
            [poolInitAmount, poolInitAmount].toMemoryArray(),
            poolInitAmount,
            false,
            bytes("")
        );

        // Add discount between 0 and 100%
        hookDiscountPercentage = bound(hookDiscountPercentage, 0, 1e18);
        PoolHooksMock(poolHooksContract).setRemoveLiquidityHookDiscountPercentage(hookDiscountPercentage);

        // Make sure bob has enough to pay for the transaction
        expectedBptIn = bound(expectedBptIn, _minBptOut, BalancerPoolToken(pool).balanceOf(bob));

        // Since bob added poolInitAmount in each token of the pool, the pool balances are doubled
        uint256[] memory actualAmountsOut = BasePoolMath.computeProportionalAmountsOut(
            [2 * poolInitAmount, 2 * poolInitAmount].toMemoryArray(),
            BalancerPoolToken(pool).totalSupply(),
            expectedBptIn
        );
        uint256 actualAmountOut = actualAmountsOut[0];
        uint256 hookDiscount = actualAmountOut.mulDown(hookDiscountPercentage);

        // Hook needs to have tokens to pay for discount, else balances do not settle
        dai.mint(poolHooksContract, hookDiscount);
        usdc.mint(poolHooksContract, hookDiscount);

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
                expectedBptIn,
                actualAmountsOut,
                actualAmountsOut,
                expectedBalances,
                bytes("")
            )
        );

        router.removeLiquidityProportional(pool, expectedBptIn, actualAmountsOut, false, bytes(""));

        _checkRemoveLiquidityHookTestResults(vars, actualAmountsOut, expectedBptIn, 0, hookDiscount);
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
}
