// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";

import { PoolMock } from "../../contracts/test/PoolMock.sol";
import { PoolHooksMock } from "../../contracts/test/PoolHooksMock.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract HookAdjustedSwapTest is BaseVaultTest {
    using CastingHelpers for address[];
    using FixedPoint for uint256;

    uint256 internal daiIdx;
    uint256 internal usdcIdx;

    uint256 private constant _minSwapAmount = 1e6;
    uint256 private _swapAmount;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        _swapAmount = poolInitAmount / 100;

        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));
    }

    function createHook() internal override returns (address) {
        // Sets all flags as false
        HookFlags memory hookFlags;
        hookFlags.enableHookAdjustedAmounts = true;
        hookFlags.shouldCallAfterSwap = true;
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

    function testFeeExactIn__Fuzz(uint256 swapAmount, uint256 hookFeePercentage) public {
        // Swap between _minSwapAmount and whole pool liquidity (pool math is linear).
        swapAmount = bound(swapAmount, _minSwapAmount, poolInitAmount);

        // Fee between 0 and 100%.
        hookFeePercentage = bound(hookFeePercentage, 0, FixedPoint.ONE);
        PoolHooksMock(poolHooksContract).setHookSwapFeePercentage(hookFeePercentage);
        uint256 hookFee = swapAmount.mulDown(hookFeePercentage);

        BaseVaultTest.Balances memory balancesBefore = getBalances(bob);

        vm.prank(bob);
        vm.expectCall(
            address(poolHooksContract),
            abi.encodeWithSelector(
                IHooks.onAfterSwap.selector,
                AfterSwapParams({
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

        BaseVaultTest.Balances memory balancesAfter = getBalances(bob);

        assertEq(
            balancesBefore.userTokens[daiIdx] - balancesAfter.userTokens[daiIdx],
            swapAmount,
            "Bob DAI balance is wrong"
        );
        assertEq(balancesBefore.hookTokens[daiIdx], balancesAfter.hookTokens[daiIdx], "Hook DAI balance is wrong");
        assertEq(
            balancesAfter.userTokens[usdcIdx] - balancesBefore.userTokens[usdcIdx],
            swapAmount - hookFee,
            "Bob USDC balance is wrong"
        );
        assertEq(
            balancesAfter.hookTokens[usdcIdx] - balancesBefore.hookTokens[usdcIdx],
            hookFee,
            "Hook USDC balance is wrong"
        );

        _checkPoolAndVaultBalances(balancesBefore, balancesAfter, swapAmount);
    }

    function testDiscountExactIn__Fuzz(uint256 swapAmount, uint256 hookDiscountPercentage) public {
        // Swap between _minSwapAmount and whole pool liquidity (pool math is linear).
        swapAmount = bound(swapAmount, _minSwapAmount, poolInitAmount);

        // Discount between 0 and 100%
        hookDiscountPercentage = bound(hookDiscountPercentage, 0, FixedPoint.ONE);
        PoolHooksMock(poolHooksContract).setHookSwapDiscountPercentage(hookDiscountPercentage);
        uint256 hookDiscount = swapAmount.mulDown(hookDiscountPercentage);

        // Hook needs to pay the discount to the pool. Since it's exact in, the discount is paid in tokenOut amount.
        usdc.mint(address(poolHooksContract), hookDiscount);

        BaseVaultTest.Balances memory balancesBefore = getBalances(bob);

        // Check that the swap gets updated balances that reflect the updated balance in the before hook.
        vm.prank(bob);
        // Check that balances were not changed before onBeforeHook.
        vm.expectCall(
            address(poolHooksContract),
            abi.encodeWithSelector(
                IHooks.onAfterSwap.selector,
                AfterSwapParams({
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

        BaseVaultTest.Balances memory balancesAfter = getBalances(bob);

        assertEq(
            balancesBefore.userTokens[daiIdx] - balancesAfter.userTokens[daiIdx],
            swapAmount,
            "Bob DAI balance is wrong"
        );
        assertEq(balancesBefore.hookTokens[daiIdx], balancesAfter.hookTokens[daiIdx], "Hook DAI balance is wrong");
        assertEq(
            balancesAfter.userTokens[usdcIdx] - balancesBefore.userTokens[usdcIdx],
            swapAmount + hookDiscount,
            "Bob USDC balance is wrong"
        );
        assertEq(
            balancesBefore.hookTokens[usdcIdx] - balancesAfter.hookTokens[usdcIdx],
            hookDiscount,
            "Hook USDC balance is wrong"
        );

        _checkPoolAndVaultBalances(balancesBefore, balancesAfter, swapAmount);
    }

    function testFeeExactOut__Fuzz(uint256 swapAmount, uint256 hookFeePercentage) public {
        // Swap between _minSwapAmount and whole pool liquidity (pool math is linear).
        swapAmount = bound(swapAmount, _minSwapAmount, poolInitAmount);

        // Fee between 0 and 100%.
        hookFeePercentage = bound(hookFeePercentage, 0, FixedPoint.ONE);
        PoolHooksMock(poolHooksContract).setHookSwapFeePercentage(hookFeePercentage);
        uint256 hookFee = swapAmount.mulDown(hookFeePercentage);

        BaseVaultTest.Balances memory balancesBefore = getBalances(bob);

        // Check that the swap gets updated balances that reflect the updated balance in the before hook.
        vm.prank(bob);
        // Check that balances were not changed before onBeforeHook.
        vm.expectCall(
            address(poolHooksContract),
            abi.encodeWithSelector(
                IHooks.onAfterSwap.selector,
                AfterSwapParams({
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

        BaseVaultTest.Balances memory balancesAfter = getBalances(bob);

        assertEq(
            balancesAfter.userTokens[usdcIdx] - balancesBefore.userTokens[usdcIdx],
            swapAmount,
            "Bob USDC balance is wrong"
        );
        assertEq(balancesBefore.hookTokens[usdcIdx], balancesAfter.hookTokens[usdcIdx], "Hook USDC balance is wrong");
        assertEq(
            balancesBefore.userTokens[daiIdx] - balancesAfter.userTokens[daiIdx],
            swapAmount + hookFee,
            "Bob DAI balance is wrong"
        );
        assertEq(
            balancesAfter.hookTokens[daiIdx] - balancesBefore.hookTokens[daiIdx],
            hookFee,
            "Hook DAI balance is wrong"
        );

        _checkPoolAndVaultBalances(balancesBefore, balancesAfter, swapAmount);
    }

    function testDiscountExactOut__Fuzz(uint256 swapAmount, uint256 hookDiscountPercentage) public {
        // Swap between _minSwapAmount and whole pool liquidity (pool math is linear).
        swapAmount = bound(swapAmount, _minSwapAmount, poolInitAmount);

        // Discount between 0 and 100%
        hookDiscountPercentage = bound(hookDiscountPercentage, 0, FixedPoint.ONE);
        PoolHooksMock(poolHooksContract).setHookSwapDiscountPercentage(hookDiscountPercentage);
        uint256 hookDiscount = swapAmount.mulDown(hookDiscountPercentage);

        // Hook needs to pay the discount to the pool. Since it's exact out, the discount is paid in tokenIn amount.
        dai.mint(address(poolHooksContract), hookDiscount);

        BaseVaultTest.Balances memory balancesBefore = getBalances(bob);

        // Check that the swap gets updated balances that reflect the updated balance in the before hook.
        vm.prank(bob);
        // Check that balances were not changed before onBeforeHook.
        vm.expectCall(
            address(poolHooksContract),
            abi.encodeWithSelector(
                IHooks.onAfterSwap.selector,
                AfterSwapParams({
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

        BaseVaultTest.Balances memory balancesAfter = getBalances(bob);

        assertEq(
            balancesAfter.userTokens[usdcIdx] - balancesBefore.userTokens[usdcIdx],
            swapAmount,
            "Bob USDC balance is wrong"
        );
        assertEq(balancesBefore.hookTokens[usdcIdx], balancesAfter.hookTokens[usdcIdx], "Hook USDC balance is wrong");
        assertEq(
            balancesBefore.userTokens[daiIdx] - balancesAfter.userTokens[daiIdx],
            swapAmount - hookDiscount,
            "Bob DAI balance is wrong"
        );
        assertEq(
            balancesBefore.hookTokens[daiIdx] - balancesAfter.hookTokens[daiIdx],
            hookDiscount,
            "Hook DAI balance is wrong"
        );

        _checkPoolAndVaultBalances(balancesBefore, balancesAfter, swapAmount);
    }

    function testFeeExactInLimitViolation() public {
        uint256 hookFeePercentage = 1e16;
        PoolHooksMock(poolHooksContract).setHookSwapFeePercentage(hookFeePercentage);
        uint256 hookFee = _swapAmount.mulDown(hookFeePercentage);

        // Check that the swap gets updated balances that reflect the updated balance in the before hook.
        vm.prank(bob);
        // Check that  onAfterHook was called with the correct params.
        vm.expectCall(
            address(poolHooksContract),
            abi.encodeWithSelector(
                IHooks.onAfterSwap.selector,
                AfterSwapParams({
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
        // Check that the call reverted because limits were not respected in the after hook (amountOut < minAmountOut).
        vm.expectRevert(
            abi.encodeWithSelector(IVaultErrors.HookAdjustedSwapLimit.selector, _swapAmount - hookFee, _swapAmount)
        );

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

    function testFeeExactOutLimitViolation() public {
        uint256 hookFeePercentage = 1e16;
        PoolHooksMock(poolHooksContract).setHookSwapFeePercentage(hookFeePercentage);
        uint256 hookFee = _swapAmount.mulDown(hookFeePercentage);

        // Check that the swap gets updated balances that reflect the updated balance in the before hook.
        vm.prank(bob);
        // Check that onAfterSwap was called with the correct parameters.
        vm.expectCall(
            address(poolHooksContract),
            abi.encodeWithSelector(
                IHooks.onAfterSwap.selector,
                AfterSwapParams({
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

        // Check that the call reverted because limits were not respected in the after hook (amountIn > maxAmountIn).
        vm.expectRevert(
            abi.encodeWithSelector(IVaultErrors.HookAdjustedSwapLimit.selector, _swapAmount + hookFee, _swapAmount)
        );

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

    function testBalanceNotSettled() public {
        uint256 hookDiscountPercentage = 1e16;
        PoolHooksMock(poolHooksContract).setHookSwapDiscountPercentage(hookDiscountPercentage);
        PoolHooksMock(poolHooksContract).setShouldSettleDiscount(false);

        // Check that the swap gets updated balances that reflect the updated balance in the before hook.
        vm.prank(bob);
        // Check that onAfterHook was called with the correct params.
        vm.expectCall(
            address(poolHooksContract),
            abi.encodeWithSelector(
                IHooks.onAfterSwap.selector,
                AfterSwapParams({
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
        // Check that the call reverted because balances were not settled.
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.BalanceNotSettled.selector));

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

    function _checkPoolAndVaultBalances(
        BaseVaultTest.Balances memory balancesBefore,
        BaseVaultTest.Balances memory balancesAfter,
        uint256 poolBalanceChange
    ) private view {
        // Considers swap fee = 0, so only hook fees and discounts occurred.
        assertEq(
            balancesAfter.poolTokens[daiIdx] - balancesBefore.poolTokens[daiIdx],
            poolBalanceChange,
            "Pool DAI balance is wrong"
        );
        assertEq(
            balancesBefore.poolTokens[usdcIdx] - balancesAfter.poolTokens[usdcIdx],
            poolBalanceChange,
            "Pool USDC balance is wrong"
        );
        assertEq(
            balancesAfter.vaultTokens[daiIdx] - balancesBefore.vaultTokens[daiIdx],
            poolBalanceChange,
            "Vault DAI balance is wrong"
        );
        assertEq(
            balancesBefore.vaultTokens[usdcIdx] - balancesAfter.vaultTokens[usdcIdx],
            poolBalanceChange,
            "Vault USDC balance is wrong"
        );
    }
}
