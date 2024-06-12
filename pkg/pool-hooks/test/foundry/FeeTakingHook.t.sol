// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { SwapKind } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";

import { FeeTakingHook } from "../../contracts/FeeTakingHook.sol";

contract FeeTakingHookTest is BaseVaultTest {
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

        _fillAfterSwapHookTestLocals(vars);

        assertEq(vars.bob.daiBefore - vars.bob.daiAfter, swapAmount, "Bob DAI balance is wrong");
        assertEq(vars.hook.daiBefore, vars.hook.daiAfter, "Hook DAI balance is wrong");
        assertEq(vars.bob.usdcAfter - vars.bob.usdcBefore, swapAmount - hookFee, "Bob USDC balance is wrong");
        assertEq(vars.hook.usdcAfter - vars.hook.usdcBefore, hookFee, "Hook USDC balance is wrong");

        _checkPoolAndVaultBalances(vars, swapAmount);
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

        _fillAfterSwapHookTestLocals(vars);

        assertEq(vars.bob.usdcAfter - vars.bob.usdcBefore, swapAmount, "Bob USDC balance is wrong");
        assertEq(vars.hook.usdcBefore, vars.hook.usdcAfter, "Hook USDC balance is wrong");
        assertEq(vars.bob.daiBefore - vars.bob.daiAfter, swapAmount + hookFee, "Bob DAI balance is wrong");
        assertEq(vars.hook.daiAfter - vars.hook.daiBefore, hookFee, "Hook DAI balance is wrong");

        _checkPoolAndVaultBalances(vars, swapAmount);
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

    function _createHookTestLocals() private returns (HookTestLocals memory vars) {
        vars.bob.daiBefore = dai.balanceOf(address(bob));
        vars.bob.usdcBefore = usdc.balanceOf(address(bob));
        vars.hook.daiBefore = dai.balanceOf(poolHooksContract);
        vars.hook.usdcBefore = usdc.balanceOf(poolHooksContract);
        vars.vault.daiBefore = dai.balanceOf(address(vault));
        vars.vault.usdcBefore = usdc.balanceOf(address(vault));
        vars.poolBefore = vault.getRawBalances(pool);
    }

    function _fillAfterSwapHookTestLocals(HookTestLocals memory vars) private {
        vars.bob.daiAfter = dai.balanceOf(address(bob));
        vars.bob.usdcAfter = usdc.balanceOf(address(bob));
        vars.hook.daiAfter = dai.balanceOf(poolHooksContract);
        vars.hook.usdcAfter = usdc.balanceOf(poolHooksContract);
        vars.vault.daiAfter = dai.balanceOf(address(vault));
        vars.vault.usdcAfter = usdc.balanceOf(address(vault));
        vars.poolAfter = vault.getRawBalances(pool);
    }

    function _checkPoolAndVaultBalances(HookTestLocals memory vars, uint256 poolBalanceChange) private {
        // Considers swap fee = 0, so only hook fees were charged
        assertEq(vars.poolAfter[daiIdx] - vars.poolBefore[daiIdx], poolBalanceChange, "Pool DAI balance is wrong");
        assertEq(vars.poolBefore[usdcIdx] - vars.poolAfter[usdcIdx], poolBalanceChange, "Pool USDC balance is wrong");
        assertEq(vars.vault.daiAfter - vars.vault.daiBefore, poolBalanceChange, "Vault DAI balance is wrong");
        assertEq(vars.vault.usdcBefore - vars.vault.usdcAfter, poolBalanceChange, "Vault USDC balance is wrong");
    }
}
