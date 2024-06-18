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

contract HookAdjustedLiquidityTest is BaseVaultTest {
    using FixedPoint for uint256;
    using ArrayHelpers for *;

    uint256 internal daiIdx;
    uint256 internal usdcIdx;

    uint256 private _swapAmount;
    uint256 private constant _minBptOut = 1e6;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        _swapAmount = poolInitAmount / 100;

        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));
    }

    function createHook() internal override returns (address) {
        IHooks.HookFlags memory hookFlags;
        hookFlags.enableHookAdjustedAmounts = true;
        hookFlags.shouldCallAfterAddLiquidity = true;
        hookFlags.shouldCallAfterRemoveLiquidity = true;
        return _createHook(hookFlags);
    }

    function testHookFeeAddLiquidityExactIn__Fuzz(uint256 expectedBptOut, uint256 hookFeePercentage) public {
        // Add fee between 0 and 100%
        hookFeePercentage = bound(hookFeePercentage, 0, 1e18);
        PoolHooksMock(poolHooksContract).setAddLiquidityHookFeePercentage(hookFeePercentage);

        // Since operation is not settled in advance, max expected bpt out can't generate a hook fee higher than
        // pool liquidity, or else the hook won't be able to charge fees
        {
            uint256 bobDaiBalance = dai.balanceOf(bob);

            // Since operation is not settled in advance, max expected bpt out can't generate a hook fee higher than
            // pool liquidity, or else the hook won't be able to charge fees
            expectedBptOut = bound(
                expectedBptOut,
                _minBptOut,
                hookFeePercentage == 0 ? bobDaiBalance : poolInitAmount.divDown(hookFeePercentage)
            );

            // Make sure bob has enough to pay for the transaction
            if (expectedBptOut > bobDaiBalance) {
                expectedBptOut = bobDaiBalance;
            }
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

        _checkAddLiquidityHookTestResults(vars, actualAmountsIn, expectedBptOut, int256(hookFee));
    }

    function testHookDiscountAddLiquidityExactIn__Fuzz(uint256 expectedBptOut, uint256 hookDiscountPercentage) public {
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
                AddLiquidityKind.PROPORTIONAL,
                actualAmountsIn,
                actualAmountsIn,
                expectedBptOut,
                expectedBalances,
                bytes("")
            )
        );

        router.addLiquidityProportional(pool, actualAmountsIn, expectedBptOut, false, bytes(""));

        _checkAddLiquidityHookTestResults(vars, actualAmountsIn, expectedBptOut, -(int256(hookDiscount)));
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

        _checkRemoveLiquidityHookTestResults(vars, actualAmountsOut, expectedBptIn, int256(hookFee));
    }

    function testHookDiscountRemoveLiquidityExactIn__Fuzz(
        uint256 expectedBptIn,
        uint256 hookDiscountPercentage
    ) public {
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
                RemoveLiquidityKind.PROPORTIONAL,
                expectedBptIn,
                actualAmountsOut,
                actualAmountsOut,
                expectedBalances,
                bytes("")
            )
        );

        router.removeLiquidityProportional(pool, expectedBptIn, actualAmountsOut, false, bytes(""));

        _checkRemoveLiquidityHookTestResults(vars, actualAmountsOut, expectedBptIn, -(int256(hookDiscount)));
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
        int256 expectedHookDelta
    ) private {
        _fillAfterHookTestLocals(vars);

        assertEq(vars.bptSupplyAfter - vars.bptSupplyBefore, expectedBptOut, "Pool Supply is wrong");
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

        assertEq(vars.vault.daiAfter - vars.vault.daiBefore, actualAmountsIn[daiIdx], "Vault DAI balance is wrong");
        assertEq(vars.vault.usdcAfter - vars.vault.usdcBefore, actualAmountsIn[usdcIdx], "Vault USDC balance is wrong");

        assertEq(vars.bob.bptAfter - vars.bob.bptBefore, expectedBptOut, "Bob BPT balance is wrong");
        assertEq(
            int256(vars.bob.daiBefore) - int256(vars.bob.daiAfter),
            int256(actualAmountsIn[daiIdx]) + expectedHookDelta,
            "Bob DAI balance is wrong"
        );
        assertEq(
            int256(vars.bob.usdcBefore) - int256(vars.bob.usdcAfter),
            int256(actualAmountsIn[usdcIdx]) + expectedHookDelta,
            "Bob USDC balance is wrong"
        );

        assertEq(
            int256(vars.hook.daiAfter) - int256(vars.hook.daiBefore),
            expectedHookDelta,
            "Hook DAI balance is wrong"
        );
        assertEq(
            int256(vars.hook.usdcAfter) - int256(vars.hook.usdcBefore),
            expectedHookDelta,
            "Hook USDC balance is wrong"
        );
    }

    function _checkRemoveLiquidityHookTestResults(
        HookTestLocals memory vars,
        uint256[] memory actualAmountsOut,
        uint256 expectedBptIn,
        int256 expectedHookDelta
    ) private {
        _fillAfterHookTestLocals(vars);

        assertEq(vars.bptSupplyBefore - vars.bptSupplyAfter, expectedBptIn, "Pool Supply is wrong");
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

        assertEq(vars.vault.daiBefore - vars.vault.daiAfter, actualAmountsOut[daiIdx], "Vault DAI balance is wrong");
        assertEq(
            vars.vault.usdcBefore - vars.vault.usdcAfter,
            actualAmountsOut[usdcIdx],
            "Vault USDC balance is wrong"
        );

        assertEq(vars.bob.bptBefore - vars.bob.bptAfter, expectedBptIn, "Bob BPT balance is wrong");
        assertEq(
            int256(vars.bob.daiAfter - vars.bob.daiBefore),
            int256(actualAmountsOut[daiIdx]) - expectedHookDelta,
            "Bob DAI balance is wrong"
        );
        assertEq(
            int256(vars.bob.usdcAfter - vars.bob.usdcBefore),
            int256(actualAmountsOut[usdcIdx]) - expectedHookDelta,
            "Bob USDC balance is wrong"
        );

        assertEq(
            int256(vars.hook.daiAfter) - int256(vars.hook.daiBefore),
            expectedHookDelta,
            "Hook DAI balance is wrong"
        );
        assertEq(
            int256(vars.hook.usdcAfter) - int256(vars.hook.usdcBefore),
            expectedHookDelta,
            "Hook USDC balance is wrong"
        );
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
