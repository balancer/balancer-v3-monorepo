// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { BasePoolMath } from "@balancer-labs/v3-solidity-utils/contracts/math/BasePoolMath.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";

import { BalancerPoolToken } from "../../contracts/BalancerPoolToken.sol";
import { PoolMock } from "../../contracts/test/PoolMock.sol";
import { PoolHooksMock } from "../../contracts/test/PoolHooksMock.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract HookAdjustedLiquidityTest is BaseVaultTest {
    using CastingHelpers for address[];
    using FixedPoint for uint256;
    using ArrayHelpers for *;

    uint256 internal daiIdx;
    uint256 internal usdcIdx;

    // Maximum fee of 10%
    uint64 public constant MAX_HOOK_FEE_PERCENTAGE = 10e16;

    uint256 private _swapAmount;
    uint256 private constant _minBptOut = 1e6;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        _swapAmount = poolInitAmount / 100;

        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));
    }

    function createHook() internal override returns (address) {
        HookFlags memory hookFlags;
        hookFlags.enableHookAdjustedAmounts = true;
        hookFlags.shouldCallAfterAddLiquidity = true;
        hookFlags.shouldCallAfterRemoveLiquidity = true;
        return _createHook(hookFlags);
    }

    // Overrides pool creation to set liquidityManagement (disables unbalanced liquidity).
    function _createPool(address[] memory tokens, string memory label) internal override returns (address) {
        PoolMock newPool = new PoolMock(IVault(address(vault)), "ERC20 Pool", "ERC20POOL");
        vm.label(address(newPool), label);

        PoolRoleAccounts memory roleAccounts;
        roleAccounts.poolCreator = lp;

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

    function testHookFeeAddLiquidity__Fuzz(uint256 expectedBptOut, uint256 hookFeePercentage) public {
        // Add fee between 0 and 100%.
        hookFeePercentage = bound(hookFeePercentage, 0, FixedPoint.ONE);
        PoolHooksMock(poolHooksContract).setAddLiquidityHookFeePercentage(hookFeePercentage);

        // Since operation is not settled in advance, max expected bpt out can't generate a hook fee higher than
        // pool liquidity, or else the hook won't be able to charge fees.
        {
            uint256 bobDaiBalance = dai.balanceOf(bob);

            // Since operation is not settled in advance, max expected bpt out can't generate a hook fee higher than
            // pool liquidity, or else the hook won't be able to charge fees.
            expectedBptOut = bound(
                expectedBptOut,
                _minBptOut * MIN_TRADE_AMOUNT,
                hookFeePercentage == 0 ? bobDaiBalance : poolInitAmount.divDown(hookFeePercentage)
            );

            // Make sure bob has enough to pay for the transaction.
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

        BaseVaultTest.Balances memory balancesBefore = getBalances(bob);

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

        _checkAddLiquidityHookTestResults(balancesBefore, actualAmountsIn, expectedBptOut, int256(hookFee));
    }

    function testHookDiscountAddLiquidity__Fuzz(uint256 expectedBptOut, uint256 hookDiscountPercentage) public {
        // Add discount between 0 and 100%.
        hookDiscountPercentage = bound(hookDiscountPercentage, 0, FixedPoint.ONE);
        PoolHooksMock(poolHooksContract).setAddLiquidityHookDiscountPercentage(hookDiscountPercentage);

        // Make sure bob has enough to pay for the transaction.
        expectedBptOut = bound(expectedBptOut, _minBptOut * MIN_TRADE_AMOUNT, dai.balanceOf(bob));

        uint256[] memory actualAmountsIn = BasePoolMath.computeProportionalAmountsIn(
            [poolInitAmount, poolInitAmount].toMemoryArray(),
            BalancerPoolToken(pool).totalSupply(),
            expectedBptOut
        );
        uint256 actualAmountIn = actualAmountsIn[0];
        uint256 hookDiscount = actualAmountIn.mulDown(hookDiscountPercentage);

        // Hook needs to have tokens to pay for discount, or else balances do not settle.
        dai.mint(poolHooksContract, hookDiscount);
        usdc.mint(poolHooksContract, hookDiscount);

        uint256[] memory expectedBalances = [poolInitAmount + actualAmountIn, poolInitAmount + actualAmountIn]
            .toMemoryArray();

        BaseVaultTest.Balances memory balancesBefore = getBalances(bob);

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

        _checkAddLiquidityHookTestResults(balancesBefore, actualAmountsIn, expectedBptOut, -(int256(hookDiscount)));
    }

    function testHookFeeAddLiquidityLimitViolation() public {
        uint256 hookFeePercentage = MAX_HOOK_FEE_PERCENTAGE;
        PoolHooksMock(poolHooksContract).setAddLiquidityHookFeePercentage(hookFeePercentage);

        uint256 expectedBptOut = poolInitAmount / 100;

        uint256[] memory actualAmountsIn = BasePoolMath.computeProportionalAmountsIn(
            [poolInitAmount, poolInitAmount].toMemoryArray(),
            BalancerPoolToken(pool).totalSupply(),
            expectedBptOut
        );
        uint256 actualAmountIn = actualAmountsIn[0];
        uint256 hookFee = actualAmountIn.mulDown(hookFeePercentage);

        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(
                IVaultErrors.HookAdjustedAmountInAboveMax.selector,
                address(dai),
                actualAmountIn + hookFee,
                actualAmountIn
            )
        );
        router.addLiquidityProportional(pool, actualAmountsIn, expectedBptOut, false, bytes(""));
    }

    function testHookFeeAddLiquidityIgnoreHookAdjusted() public {
        HooksConfig memory config = vault.getHooksConfig(pool);
        config.enableHookAdjustedAmounts = false;
        vault.manualSetHooksConfig(pool, config);

        uint256 hookFeePercentage = MAX_HOOK_FEE_PERCENTAGE;
        PoolHooksMock(poolHooksContract).setAddLiquidityHookFeePercentage(hookFeePercentage);

        uint256 expectedBptOut = poolInitAmount / 100;

        uint256[] memory actualAmountsIn = BasePoolMath.computeProportionalAmountsIn(
            [poolInitAmount, poolInitAmount].toMemoryArray(),
            BalancerPoolToken(pool).totalSupply(),
            expectedBptOut
        );

        vm.prank(bob);
        // Since hook charged the fee but the hook adjusted value was ignored, balances didn't settle.
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.BalanceNotSettled.selector));
        router.addLiquidityProportional(pool, actualAmountsIn, expectedBptOut, false, bytes(""));
    }

    function testHookFeeRemoveLiquidity__Fuzz(uint256 expectedBptIn, uint256 hookFeePercentage) public {
        // Add liquidity so Bob has BPT to remove liquidity.
        vm.prank(bob);
        router.addLiquidityProportional(
            pool,
            [poolInitAmount, poolInitAmount].toMemoryArray(),
            2 * poolInitAmount,
            false,
            bytes("")
        );

        // Add fee between 0 and 100%.
        hookFeePercentage = bound(hookFeePercentage, 0, FixedPoint.ONE);
        PoolHooksMock(poolHooksContract).setRemoveLiquidityHookFeePercentage(hookFeePercentage);

        // Make sure Bob has enough to pay for the transaction.
        expectedBptIn = bound(expectedBptIn, _minBptOut * MIN_TRADE_AMOUNT, BalancerPoolToken(pool).balanceOf(bob));

        // Since Bob added poolInitAmount in each token of the pool, the pool balances are doubled.
        uint256[] memory actualAmountsOut = BasePoolMath.computeProportionalAmountsOut(
            [2 * poolInitAmount, 2 * poolInitAmount].toMemoryArray(),
            BalancerPoolToken(pool).totalSupply(),
            expectedBptIn
        );
        uint256 actualAmountOut = actualAmountsOut[0];
        uint256 hookFee = actualAmountOut.mulDown(hookFeePercentage);

        uint256[] memory expectedBalances = [2 * poolInitAmount - actualAmountOut, 2 * poolInitAmount - actualAmountOut]
            .toMemoryArray();

        BaseVaultTest.Balances memory balancesBefore = getBalances(bob);

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

        _checkRemoveLiquidityHookTestResults(balancesBefore, actualAmountsOut, expectedBptIn, int256(hookFee));
    }

    function testHookDiscountRemoveLiquidity__Fuzz(uint256 expectedBptIn, uint256 hookDiscountPercentage) public {
        // Add liquidity so Bob has BPT to remove liquidity.
        vm.prank(bob);
        router.addLiquidityProportional(
            pool,
            [poolInitAmount, poolInitAmount].toMemoryArray(),
            2 * poolInitAmount,
            false,
            bytes("")
        );

        // Add discount between 0 and 100%.
        hookDiscountPercentage = bound(hookDiscountPercentage, 0, FixedPoint.ONE);
        PoolHooksMock(poolHooksContract).setRemoveLiquidityHookDiscountPercentage(hookDiscountPercentage);

        // Make sure Bob has enough to pay for the transaction.
        expectedBptIn = bound(expectedBptIn, _minBptOut * MIN_TRADE_AMOUNT, BalancerPoolToken(pool).balanceOf(bob));

        // Since Bob added poolInitAmount in each token of the pool, the pool balances are doubled.
        uint256[] memory actualAmountsOut = BasePoolMath.computeProportionalAmountsOut(
            [2 * poolInitAmount, 2 * poolInitAmount].toMemoryArray(),
            BalancerPoolToken(pool).totalSupply(),
            expectedBptIn
        );
        uint256 actualAmountOut = actualAmountsOut[0];
        uint256 hookDiscount = actualAmountOut.mulDown(hookDiscountPercentage);

        // Hook needs to have tokens to pay for discount, or else balances do not settle.
        dai.mint(poolHooksContract, hookDiscount);
        usdc.mint(poolHooksContract, hookDiscount);

        uint256[] memory expectedBalances = [2 * poolInitAmount - actualAmountOut, 2 * poolInitAmount - actualAmountOut]
            .toMemoryArray();

        BaseVaultTest.Balances memory balancesBefore = getBalances(bob);

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

        _checkRemoveLiquidityHookTestResults(balancesBefore, actualAmountsOut, expectedBptIn, -(int256(hookDiscount)));
    }

    function testHookFeeRemoveLiquidityLimitViolation() public {
        // Add liquidity so Bob has BPT to remove liquidity.
        vm.prank(bob);
        router.addLiquidityProportional(
            pool,
            [poolInitAmount, poolInitAmount].toMemoryArray(),
            2 * poolInitAmount,
            false,
            bytes("")
        );

        uint256 hookFeePercentage = MAX_HOOK_FEE_PERCENTAGE;
        PoolHooksMock(poolHooksContract).setRemoveLiquidityHookFeePercentage(hookFeePercentage);

        // 10% of Bob's liquidity.
        uint256 expectedBptIn = BalancerPoolToken(pool).balanceOf(bob) / 10;

        // Since Bob added poolInitAmount in each token of the pool, the pool balances are doubled.
        uint256[] memory actualAmountsOut = BasePoolMath.computeProportionalAmountsOut(
            [2 * poolInitAmount, 2 * poolInitAmount].toMemoryArray(),
            BalancerPoolToken(pool).totalSupply(),
            expectedBptIn
        );
        uint256 actualAmountOut = actualAmountsOut[0];
        uint256 hookFee = actualAmountOut.mulDown(hookFeePercentage);

        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(
                IVaultErrors.HookAdjustedAmountOutBelowMin.selector,
                address(dai),
                actualAmountOut - hookFee,
                actualAmountOut
            )
        );
        router.removeLiquidityProportional(pool, expectedBptIn, actualAmountsOut, false, bytes(""));
    }

    function testHookFeeRemoveLiquidityIgnoreHookAdjusted() public {
        HooksConfig memory config = vault.getHooksConfig(pool);
        config.enableHookAdjustedAmounts = false;
        vault.manualSetHooksConfig(pool, config);

        // Add liquidity so Bob has BPT to remove liquidity.
        vm.prank(bob);
        router.addLiquidityProportional(
            pool,
            [poolInitAmount, poolInitAmount].toMemoryArray(),
            2 * poolInitAmount,
            false,
            bytes("")
        );

        uint256 hookFeePercentage = MAX_HOOK_FEE_PERCENTAGE;
        PoolHooksMock(poolHooksContract).setRemoveLiquidityHookFeePercentage(hookFeePercentage);

        // 10% of Bob's liquidity.
        uint256 expectedBptIn = BalancerPoolToken(pool).balanceOf(bob) / 10;

        // Since Bob added poolInitAmount in each token of the pool, the pool balances are doubled.
        uint256[] memory actualAmountsOut = BasePoolMath.computeProportionalAmountsOut(
            [2 * poolInitAmount, 2 * poolInitAmount].toMemoryArray(),
            BalancerPoolToken(pool).totalSupply(),
            expectedBptIn
        );

        vm.prank(bob);
        // Since hook charged the fee but the hook adjusted value was ignored, balances didn't settle.
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.BalanceNotSettled.selector));
        router.removeLiquidityProportional(pool, expectedBptIn, actualAmountsOut, false, bytes(""));
    }

    function _checkAddLiquidityHookTestResults(
        BaseVaultTest.Balances memory balancesBefore,
        uint256[] memory actualAmountsIn,
        uint256 expectedBptOut,
        int256 expectedHookDelta
    ) private view {
        BaseVaultTest.Balances memory balancesAfter = getBalances(bob);

        assertEq(balancesAfter.poolSupply - balancesBefore.poolSupply, expectedBptOut, "Pool Supply is wrong");
        assertEq(
            balancesAfter.poolTokens[daiIdx] - balancesBefore.poolTokens[daiIdx],
            actualAmountsIn[daiIdx],
            "Pool DAI balance is wrong"
        );
        assertEq(
            balancesAfter.poolTokens[usdcIdx] - balancesBefore.poolTokens[usdcIdx],
            actualAmountsIn[usdcIdx],
            "Pool USDC balance is wrong"
        );

        assertEq(
            balancesAfter.vaultTokens[daiIdx] - balancesBefore.vaultTokens[daiIdx],
            actualAmountsIn[daiIdx],
            "Vault DAI balance is wrong"
        );
        assertEq(
            balancesAfter.vaultTokens[usdcIdx] - balancesBefore.vaultTokens[usdcIdx],
            actualAmountsIn[usdcIdx],
            "Vault USDC balance is wrong"
        );

        assertEq(balancesAfter.userBpt - balancesBefore.userBpt, expectedBptOut, "Bob BPT balance is wrong");
        assertEq(
            int256(balancesBefore.userTokens[daiIdx]) - int256(balancesAfter.userTokens[daiIdx]),
            int256(actualAmountsIn[daiIdx]) + expectedHookDelta,
            "Bob DAI balance is wrong"
        );
        assertEq(
            int256(balancesBefore.userTokens[usdcIdx]) - int256(balancesAfter.userTokens[usdcIdx]),
            int256(actualAmountsIn[usdcIdx]) + expectedHookDelta,
            "Bob USDC balance is wrong"
        );

        assertEq(
            int256(balancesAfter.hookTokens[daiIdx]) - int256(balancesBefore.hookTokens[daiIdx]),
            expectedHookDelta,
            "Hook DAI balance is wrong"
        );
        assertEq(
            int256(balancesAfter.hookTokens[usdcIdx]) - int256(balancesBefore.hookTokens[usdcIdx]),
            expectedHookDelta,
            "Hook USDC balance is wrong"
        );
    }

    function _checkRemoveLiquidityHookTestResults(
        BaseVaultTest.Balances memory balancesBefore,
        uint256[] memory actualAmountsOut,
        uint256 expectedBptIn,
        int256 expectedHookDelta
    ) private view {
        BaseVaultTest.Balances memory balancesAfter = getBalances(bob);

        assertEq(balancesBefore.poolSupply - balancesAfter.poolSupply, expectedBptIn, "Pool Supply is wrong");
        assertEq(
            balancesBefore.poolTokens[daiIdx] - balancesAfter.poolTokens[daiIdx],
            actualAmountsOut[daiIdx],
            "Pool DAI balance is wrong"
        );
        assertEq(
            balancesBefore.poolTokens[usdcIdx] - balancesAfter.poolTokens[usdcIdx],
            actualAmountsOut[usdcIdx],
            "Pool USDC balance is wrong"
        );

        assertEq(
            balancesBefore.vaultTokens[daiIdx] - balancesAfter.vaultTokens[daiIdx],
            actualAmountsOut[daiIdx],
            "Vault DAI balance is wrong"
        );
        assertEq(
            balancesBefore.vaultTokens[usdcIdx] - balancesAfter.vaultTokens[usdcIdx],
            actualAmountsOut[usdcIdx],
            "Vault USDC balance is wrong"
        );

        assertEq(balancesBefore.userBpt - balancesAfter.userBpt, expectedBptIn, "Bob BPT balance is wrong");
        assertEq(
            int256(balancesAfter.userTokens[daiIdx] - balancesBefore.userTokens[daiIdx]),
            int256(actualAmountsOut[daiIdx]) - expectedHookDelta,
            "Bob DAI balance is wrong"
        );
        assertEq(
            int256(balancesAfter.userTokens[usdcIdx] - balancesBefore.userTokens[usdcIdx]),
            int256(actualAmountsOut[usdcIdx]) - expectedHookDelta,
            "Bob USDC balance is wrong"
        );

        assertEq(
            int256(balancesAfter.hookTokens[daiIdx]) - int256(balancesBefore.hookTokens[daiIdx]),
            expectedHookDelta,
            "Hook DAI balance is wrong"
        );
        assertEq(
            int256(balancesAfter.hookTokens[usdcIdx]) - int256(balancesBefore.hookTokens[usdcIdx]),
            expectedHookDelta,
            "Hook USDC balance is wrong"
        );
    }
}
