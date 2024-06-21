// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import {
    AddLiquidityKind,
    LiquidityManagement,
    PoolRoleAccounts,
    RemoveLiquidityKind,
    SwapKind
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { BasePoolMath } from "@balancer-labs/v3-solidity-utils/contracts/math/BasePoolMath.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";
import { MeasureBalancesHelper } from "@balancer-labs/v3-vault/test/foundry/utils/MeasureBalancesHelper.sol";
import { BalancerPoolToken } from "@balancer-labs/v3-vault/contracts/BalancerPoolToken.sol";
import { PoolMock } from "@balancer-labs/v3-vault/contracts/test/PoolMock.sol";

import { FeeTakingHookExample } from "../../contracts/FeeTakingHookExample.sol";

contract FeeTakingHookExampleTest is BaseVaultTest, MeasureBalancesHelper {
    using FixedPoint for uint256;
    using ArrayHelpers for *;

    uint256 internal daiIdx;
    uint256 internal usdcIdx;

    uint256 private constant _minSwapAmount = 1e6;
    uint256 private constant _minBptOut = 1e6;

    function setUp() public virtual override {
        BaseVaultTest.setUp();
        MeasureBalancesHelper.prepareMeasurement(dai, usdc, pool, poolHooksContract, address(bob), address(lp), vault);

        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));
    }

    // Sets the hook of the pool and stores the address in the variable poolHooksContract
    function createHook() internal override returns (address) {
        // lp will be the owner of the hook. Only LP is able to set hook fee percentages.
        vm.prank(lp);
        FeeTakingHookExample hook = new FeeTakingHookExample(IVault(address(vault)));
        return address(hook);
    }

    // Overrides pool creation to set liquidityManagement (disables unbalanced liquidity)
    function _createPool(address[] memory tokens, string memory label) internal override returns (address) {
        PoolMock newPool = new PoolMock(IVault(address(vault)), "ERC20 Pool", "ERC20POOL");
        vm.label(address(newPool), label);

        PoolRoleAccounts memory roleAccounts;
        roleAccounts.poolCreator = address(lp);

        LiquidityManagement memory liquidityManagement;
        liquidityManagement.disableUnbalancedLiquidity = true;

        factoryMock.registerPool(
            address(newPool),
            vault.buildTokenConfig(tokens.asIERC20()),
            roleAccounts,
            poolHooksContract,
            liquidityManagement
        );

        return address(newPool);
    }

    function testFeeSwapExactIn__Fuzz(uint256 swapAmount, uint64 hookFeePercentage) public {
        // Swap between _minSwapAmount and whole pool liquidity (pool math is linear)
        swapAmount = bound(swapAmount, _minSwapAmount, poolInitAmount);

        // Fee between 0 and 100%
        hookFeePercentage = uint64(bound(hookFeePercentage, 0, 1e18));
        vm.prank(lp);
        FeeTakingHookExample(poolHooksContract).setHookSwapFeePercentage(hookFeePercentage);
        uint256 hookFee = swapAmount.mulDown(hookFeePercentage);

        HookTestLocals memory vars = _measureBalancesBeforeOperation();

        vm.prank(bob);
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

        _measureBalancesAfterOperation(vars);

        assertEq(vars.bob.daiBefore - vars.bob.daiAfter, swapAmount, "Bob DAI balance is wrong");
        assertEq(vars.hook.daiBefore, vars.hook.daiAfter, "Hook DAI balance is wrong");
        assertEq(vars.bob.usdcAfter - vars.bob.usdcBefore, swapAmount - hookFee, "Bob USDC balance is wrong");
        assertEq(vars.hook.usdcAfter - vars.hook.usdcBefore, hookFee, "Hook USDC balance is wrong");

        _checkPoolAndVaultBalancesAfterSwap(vars, swapAmount);
    }

    function testFeeSwapExactOut__Fuzz(uint256 swapAmount, uint64 hookFeePercentage) public {
        // Swap between _minSwapAmount and whole pool liquidity (pool math is linear)
        swapAmount = bound(swapAmount, _minSwapAmount, poolInitAmount);

        // Fee between 0 and 100%
        hookFeePercentage = uint64(bound(hookFeePercentage, 0, 1e18));
        vm.prank(lp);
        FeeTakingHookExample(poolHooksContract).setHookSwapFeePercentage(hookFeePercentage);
        uint256 hookFee = swapAmount.mulDown(hookFeePercentage);

        HookTestLocals memory vars = _measureBalancesBeforeOperation();

        vm.prank(bob);
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

        _measureBalancesAfterOperation(vars);

        assertEq(vars.bob.usdcAfter - vars.bob.usdcBefore, swapAmount, "Bob USDC balance is wrong");
        assertEq(vars.hook.usdcBefore, vars.hook.usdcAfter, "Hook USDC balance is wrong");
        assertEq(vars.bob.daiBefore - vars.bob.daiAfter, swapAmount + hookFee, "Bob DAI balance is wrong");
        assertEq(vars.hook.daiAfter - vars.hook.daiBefore, hookFee, "Hook DAI balance is wrong");

        _checkPoolAndVaultBalancesAfterSwap(vars, swapAmount);
    }

    function testHookFeeAddLiquidityExactIn__Fuzz(uint256 expectedBptOut, uint64 hookFeePercentage) public {
        // Add fee between 0 and 100%
        hookFeePercentage = uint64(bound(hookFeePercentage, 0, 1e18));
        vm.prank(lp);
        FeeTakingHookExample(poolHooksContract).setAddLiquidityHookFeePercentage(hookFeePercentage);

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

        HookTestLocals memory vars = _measureBalancesBeforeOperation();

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

        _checkAddLiquidityHookTestResults(vars, actualAmountsIn, expectedBptOut, hookFee);
    }

    function testHookFeeRemoveLiquidityExactIn__Fuzz(uint256 expectedBptIn, uint64 hookFeePercentage) public {
        // Add liquidity so bob has BPT to remove liquidity
        vm.prank(bob);
        router.addLiquidityProportional(
            pool,
            [poolInitAmount, poolInitAmount].toMemoryArray(),
            2 * poolInitAmount,
            false,
            bytes("")
        );

        // Add fee between 0 and 100%
        hookFeePercentage = uint64(bound(hookFeePercentage, 0, 1e18));
        vm.prank(lp);
        FeeTakingHookExample(poolHooksContract).setRemoveLiquidityHookFeePercentage(hookFeePercentage);

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

        HookTestLocals memory vars = _measureBalancesBeforeOperation();

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

        _checkRemoveLiquidityHookTestResults(vars, actualAmountsOut, expectedBptIn, hookFee);
    }

    function _checkPoolAndVaultBalancesAfterSwap(HookTestLocals memory vars, uint256 poolBalanceChange) private view {
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
        uint256 expectedHookFee
    ) private view {
        _measureBalancesAfterOperation(vars);

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
    }

    function _checkRemoveLiquidityHookTestResults(
        HookTestLocals memory vars,
        uint256[] memory actualAmountsOut,
        uint256 expectedBptIn,
        uint256 expectedHookFee
    ) private view {
        _measureBalancesAfterOperation(vars);

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
    }
}
