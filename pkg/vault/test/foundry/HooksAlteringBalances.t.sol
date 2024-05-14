// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IPoolHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IPoolHooks.sol";
import { IPoolLiquidity } from "@balancer-labs/v3-interfaces/contracts/vault/IPoolLiquidity.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";

import { PoolMock } from "../../contracts/test/PoolMock.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract HooksAlteringBalancesTest is BaseVaultTest {
    using ArrayHelpers for *;

    uint256 internal daiIdx;
    uint256 internal usdcIdx;

    uint256 private _swapAmount;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        _swapAmount = poolInitAmount / 100;

        PoolConfig memory config = vault.getPoolConfig(address(pool));
        config.hooks.shouldCallBeforeSwap = true;
        vault.setConfig(address(pool), config);

        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));
    }

    function createPool() internal virtual override returns (address) {
        TokenConfig[] memory tokenConfig = vault.buildTokenConfig(
            [address(dai), address(usdc)].toMemoryArray().asIERC20()
        );

        PoolMock newPool = new PoolMock(IVault(address(vault)), "ERC20 Pool", "ERC20POOL");
        vm.label(address(newPool), "pool");

        factoryMock.registerTestPool(address(newPool), tokenConfig, address(lp));

        return address(newPool);
    }

    function testOnBeforeSwapHookAltersBalances() public {
        uint256[] memory originalBalances = [poolInitAmount, poolInitAmount].toMemoryArray();
        // newBalances are raw and scaled18, because rate is 1 and decimals are 18
        uint256[] memory newBalances = [poolInitAmount / 2, poolInitAmount / 3].toMemoryArray();

        // Change balances of the pool on before hook
        PoolMock(pool).setChangePoolBalancesOnBeforeSwapHook(true, newBalances);

        // Check that the swap gets updated balances that reflect the updated balance in the before hook
        vm.prank(bob);
        // Check if balances were not changed before onBeforeHook
        vm.expectCall(
            address(pool),
            abi.encodeWithSelector(
                IPoolHooks.onBeforeSwap.selector,
                IBasePool.PoolSwapParams({
                    kind: SwapKind.EXACT_IN,
                    amountGivenScaled18: _swapAmount,
                    balancesScaled18: originalBalances,
                    indexIn: daiIdx,
                    indexOut: usdcIdx,
                    sender: address(router),
                    userData: bytes("")
                })
            )
        );

        vm.expectCall(
            address(pool),
            abi.encodeWithSelector(
                IBasePool.onSwap.selector,
                IBasePool.PoolSwapParams({
                    kind: SwapKind.EXACT_IN,
                    amountGivenScaled18: _swapAmount,
                    balancesScaled18: newBalances,
                    indexIn: daiIdx,
                    indexOut: usdcIdx,
                    sender: address(router),
                    userData: bytes("")
                })
            )
        );

        router.swapSingleTokenExactIn(address(pool), dai, usdc, _swapAmount, 0, MAX_UINT256, false, bytes(""));
    }

    function testOnBeforeAddLiquidityHookAltersBalances() public {
        PoolConfig memory config = vault.getPoolConfig(address(pool));
        config.hooks.shouldCallBeforeAddLiquidity = true;
        config.hooks.shouldCallAfterAddLiquidity = true;
        vault.setConfig(address(pool), config);

        uint256[] memory originalBalances = [poolInitAmount, poolInitAmount].toMemoryArray();
        // newBalances are raw and scaled18, because rate is 1 and decimals are 18
        uint256[] memory newBalances = [poolInitAmount / 2, poolInitAmount / 3].toMemoryArray();
        uint256[] memory amountsIn = [defaultAmount, defaultAmount].toMemoryArray();
        uint256[] memory expectedBalances = [newBalances[0] + amountsIn[0], newBalances[1] + amountsIn[1]]
            .toMemoryArray();

        // - initial BPT supply = 2 * poolInitAmount
        // - initial pool balance = [poolInitAmount, poolInitAmount]
        // - new pool balance = [poolInitAmount / 2, poolInitAmount / 3]
        // BPT supply is still the same, and amountsIn raw and scaled18 are the same, so:
        // - BPT/token = 2 * poolInitAmount / (poolInitAmount/2 + poolInitAmount/3) = 12/5
        // - expectedBptOut = BPT/token * newTokens = 12/5 * (amountsIn[0] + amountsIn[1])
        uint256 expectedBptOut = (12 * (amountsIn[0] + amountsIn[1])) / 5;

        // Change balances of the pool on before hook
        PoolMock(pool).setChangePoolBalancesOnBeforeAddLiquidityHook(true, newBalances);

        vm.prank(bob);
        // Check if balances were not changed before onBeforeHook
        vm.expectCall(
            address(pool),
            abi.encodeWithSelector(
                IPoolHooks.onBeforeAddLiquidity.selector,
                bob,
                AddLiquidityKind.CUSTOM,
                amountsIn,
                bptAmountRoundDown,
                originalBalances,
                bytes("")
            )
        );

        vm.expectCall(
            address(pool),
            abi.encodeWithSelector(
                IPoolLiquidity.onAddLiquidityCustom.selector,
                bob,
                amountsIn,
                bptAmountRoundDown,
                newBalances,
                bytes("")
            )
        );

        router.addLiquidityCustom(
            address(pool),
            amountsIn,
            bptAmountRoundDown,
            false,
            bytes("")
        );
    }

    function testOnBeforeRemoveLiquidityHookAlterBalance() public {
        PoolConfig memory config = vault.getPoolConfig(address(pool));
        config.hooks.shouldCallBeforeRemoveLiquidity = true;
        vault.setConfig(address(pool), config);

        uint256[] memory amountsOut = [defaultAmount, defaultAmount].toMemoryArray();

        vm.prank(alice);
        // Add liquidity to have BPTs to remove liquidity later
        router.addLiquidityUnbalanced(address(pool), amountsOut, 0, false, bytes(""));

        uint256 balanceAfterLiquidity = poolInitAmount + defaultAmount;

        uint256[] memory originalBalances = [balanceAfterLiquidity, balanceAfterLiquidity].toMemoryArray();
        // We set balances to something related to balanceAfterLiquidity because bptAmountsOut is simpler to calculate.
        // newBalances are raw and scaled18, because rate is 1 and decimals are 18
        uint256[] memory newBalances = [2 * balanceAfterLiquidity, 3 * balanceAfterLiquidity].toMemoryArray();

        // Change balances of the pool on before hook
        PoolMock(pool).setChangePoolBalancesOnBeforeRemoveLiquidityHook(true, newBalances);

        // Check if balances were not changed before onBeforeHook
        vm.expectCall(
            address(pool),
            abi.encodeWithSelector(
                IPoolHooks.onBeforeRemoveLiquidity.selector,
                alice,
                RemoveLiquidityKind.CUSTOM,
                bptAmount,
                amountsOut,
                originalBalances,
                bytes("")
            )
        );

        // removeLiquidityCustom passes the minAmountsOut to the callback, so we can check that they are updated.
        vm.expectCall(
            address(pool),
            abi.encodeWithSelector(
                IPoolLiquidity.onRemoveLiquidityCustom.selector,
                alice,
                bptAmount,
                amountsOut,
                newBalances,
                bytes("")
            )
        );
        vm.prank(alice);
        router.removeLiquidityCustom(address(pool), bptAmount, amountsOut, false, bytes(""));
    }
}
