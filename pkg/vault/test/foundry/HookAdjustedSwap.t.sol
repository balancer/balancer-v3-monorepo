// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";

import { PoolMock } from "../../contracts/test/PoolMock.sol";
import { PoolHooksMock } from "../../contracts/test/PoolHooksMock.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract HookAdjustedSwapTest is BaseVaultTest {
    using FixedPoint for uint256;
    using ArrayHelpers for *;

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
        IHooks.HookFlags memory hookFlags;
        hookFlags.enableHookAdjustedAmounts = true;
        hookFlags.shouldCallAfterSwap = true;
        return _createHook(hookFlags);
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

    function testFeeExactIn__Fuzz(uint256 swapAmount, uint256 hookFeePercentage) public {
        // Swap between _minSwapAmount and whole pool liquidity (pool math is linear)
        swapAmount = bound(swapAmount, _minSwapAmount, poolInitAmount);

        // Fee between 0 and 100%
        hookFeePercentage = bound(hookFeePercentage, 0, 1e18);
        PoolHooksMock(poolHooksContract).setHookSwapFeePercentage(hookFeePercentage);
        uint256 hookFee = swapAmount.mulDown(hookFeePercentage);

        HookTestLocals memory vars = _createHookTestLocals();

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

        _fillAfterSwapHookTestLocals(vars);

        assertEq(vars.bob.daiBefore - vars.bob.daiAfter, swapAmount, "Bob DAI balance is wrong");
        assertEq(vars.hook.daiBefore, vars.hook.daiAfter, "Hook DAI balance is wrong");
        assertEq(vars.bob.usdcAfter - vars.bob.usdcBefore, swapAmount - hookFee, "Bob USDC balance is wrong");
        assertEq(vars.hook.usdcAfter - vars.hook.usdcBefore, hookFee, "Hook USDC balance is wrong");

        _checkPoolAndVaultBalances(vars, swapAmount);
    }

    function testDiscountExactIn__Fuzz(uint256 swapAmount, uint256 hookDiscountPercentage) public {
        // Swap between _minSwapAmount and whole pool liquidity (pool math is linear)
        swapAmount = bound(swapAmount, _minSwapAmount, poolInitAmount);

        // Discount between 0 and 100%
        hookDiscountPercentage = bound(hookDiscountPercentage, 0, 1e18);
        PoolHooksMock(poolHooksContract).setHookSwapDiscountPercentage(hookDiscountPercentage);
        uint256 hookDiscount = swapAmount.mulDown(hookDiscountPercentage);

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

        _fillAfterSwapHookTestLocals(vars);

        assertEq(vars.bob.daiBefore - vars.bob.daiAfter, swapAmount, "Bob DAI balance is wrong");
        assertEq(vars.hook.daiBefore, vars.hook.daiAfter, "Hook DAI balance is wrong");
        assertEq(vars.bob.usdcAfter - vars.bob.usdcBefore, swapAmount + hookDiscount, "Bob USDC balance is wrong");
        assertEq(vars.hook.usdcBefore - vars.hook.usdcAfter, hookDiscount, "Hook USDC balance is wrong");

        _checkPoolAndVaultBalances(vars, swapAmount);
    }

    function testFeeExactOut__Fuzz(uint256 swapAmount, uint256 hookFeePercentage) public {
        // Swap between _minSwapAmount and whole pool liquidity (pool math is linear)
        swapAmount = bound(swapAmount, _minSwapAmount, poolInitAmount);

        // Fee between 0 and 100%
        hookFeePercentage = bound(hookFeePercentage, 0, 1e18);
        PoolHooksMock(poolHooksContract).setHookSwapFeePercentage(hookFeePercentage);
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

        _fillAfterSwapHookTestLocals(vars);

        assertEq(vars.bob.usdcAfter - vars.bob.usdcBefore, swapAmount, "Bob USDC balance is wrong");
        assertEq(vars.hook.usdcBefore, vars.hook.usdcAfter, "Hook USDC balance is wrong");
        assertEq(vars.bob.daiBefore - vars.bob.daiAfter, swapAmount + hookFee, "Bob DAI balance is wrong");
        assertEq(vars.hook.daiAfter - vars.hook.daiBefore, hookFee, "Hook DAI balance is wrong");

        _checkPoolAndVaultBalances(vars, swapAmount);
    }

    function testDiscountExactOut__Fuzz(uint256 swapAmount, uint256 hookDiscountPercentage) public {
        // Swap between _minSwapAmount and whole pool liquidity (pool math is linear)
        swapAmount = bound(swapAmount, _minSwapAmount, poolInitAmount);

        // Discount between 0 and 100%
        hookDiscountPercentage = bound(hookDiscountPercentage, 0, 1e18);
        PoolHooksMock(poolHooksContract).setHookSwapDiscountPercentage(hookDiscountPercentage);
        uint256 hookDiscount = swapAmount.mulDown(hookDiscountPercentage);

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

        _fillAfterSwapHookTestLocals(vars);

        assertEq(vars.bob.usdcAfter - vars.bob.usdcBefore, swapAmount, "Bob USDC balance is wrong");
        assertEq(vars.hook.usdcBefore, vars.hook.usdcAfter, "Hook USDC balance is wrong");
        assertEq(vars.bob.daiBefore - vars.bob.daiAfter, swapAmount - hookDiscount, "Bob DAI balance is wrong");
        assertEq(vars.hook.daiBefore - vars.hook.daiAfter, hookDiscount, "Hook DAI balance is wrong");

        _checkPoolAndVaultBalances(vars, swapAmount);
    }

    function testFeeExactInLimitViolation() public {
        uint256 hookFeePercentage = 1e16;
        PoolHooksMock(poolHooksContract).setHookSwapFeePercentage(hookFeePercentage);
        uint256 hookFee = _swapAmount.mulDown(hookFeePercentage);

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
        // Check if call reverted because balances are not settled
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

    function _createHookTestLocals() private view returns (HookTestLocals memory vars) {
        vars.bob.daiBefore = dai.balanceOf(address(bob));
        vars.bob.usdcBefore = usdc.balanceOf(address(bob));
        vars.hook.daiBefore = dai.balanceOf(poolHooksContract);
        vars.hook.usdcBefore = usdc.balanceOf(poolHooksContract);
        vars.vault.daiBefore = dai.balanceOf(address(vault));
        vars.vault.usdcBefore = usdc.balanceOf(address(vault));
        vars.poolBefore = vault.getRawBalances(pool);
    }

    function _fillAfterSwapHookTestLocals(HookTestLocals memory vars) private view {
        vars.bob.daiAfter = dai.balanceOf(address(bob));
        vars.bob.usdcAfter = usdc.balanceOf(address(bob));
        vars.hook.daiAfter = dai.balanceOf(poolHooksContract);
        vars.hook.usdcAfter = usdc.balanceOf(poolHooksContract);
        vars.vault.daiAfter = dai.balanceOf(address(vault));
        vars.vault.usdcAfter = usdc.balanceOf(address(vault));
        vars.poolAfter = vault.getRawBalances(pool);
    }

    function _checkPoolAndVaultBalances(HookTestLocals memory vars, uint256 poolBalanceChange) private view {
        // Considers swap fee = 0, so only hook fees and discounts occurred
        assertEq(vars.poolAfter[daiIdx] - vars.poolBefore[daiIdx], poolBalanceChange, "Pool DAI balance is wrong");
        assertEq(vars.poolBefore[usdcIdx] - vars.poolAfter[usdcIdx], poolBalanceChange, "Pool USDC balance is wrong");
        assertEq(vars.vault.daiAfter - vars.vault.daiBefore, poolBalanceChange, "Vault DAI balance is wrong");
        assertEq(vars.vault.usdcBefore - vars.vault.usdcAfter, poolBalanceChange, "Vault USDC balance is wrong");
    }
}
