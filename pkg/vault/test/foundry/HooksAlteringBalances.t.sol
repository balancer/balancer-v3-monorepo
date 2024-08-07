// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IPoolLiquidity } from "@balancer-labs/v3-interfaces/contracts/vault/IPoolLiquidity.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";

import { PoolMock } from "../../contracts/test/PoolMock.sol";
import { PoolHooksMock } from "../../contracts/test/PoolHooksMock.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract HooksAlteringBalancesTest is BaseVaultTest {
    using CastingHelpers for address[];
    using ArrayHelpers for *;

    uint256 internal daiIdx;
    uint256 internal usdcIdx;

    uint256 private _swapAmount;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        _swapAmount = poolInitAmount / 100;

        HooksConfig memory config = vault.getHooksConfig(pool);
        config.shouldCallBeforeSwap = true;
        vault.manualSetHooksConfig(pool, config);

        // Sets the pool address in the hook, so we can change pool balances inside the hook.
        PoolHooksMock(poolHooksContract).setPool(pool);

        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));
    }

    function createPool() internal virtual override returns (address) {
        TokenConfig[] memory tokenConfig = vault.buildTokenConfig(
            [address(dai), address(usdc)].toMemoryArray().asIERC20()
        );

        PoolMock newPool = new PoolMock(IVault(address(vault)), "ERC20 Pool", "ERC20POOL");
        vm.label(address(newPool), "pool");

        factoryMock.registerTestPool(address(newPool), tokenConfig, poolHooksContract, lp);

        return address(newPool);
    }

    function testOnBeforeSwapHookAltersBalances() public {
        uint256[] memory originalBalances = [poolInitAmount, poolInitAmount].toMemoryArray();
        // `newBalances` are raw and scaled18, because rate is 1 and decimals are 18.
        uint256[] memory newBalances = [poolInitAmount / 2, poolInitAmount / 3].toMemoryArray();

        // Change balances of the pool on before hook.
        PoolHooksMock(poolHooksContract).setChangePoolBalancesOnBeforeSwapHook(true, newBalances);

        // Check that the swap gets updated balances that reflect the updated balance in the before hook.
        vm.prank(bob);
        // Check that balances were not changed before onBeforeHook.
        vm.expectCall(
            address(poolHooksContract),
            abi.encodeWithSelector(
                IHooks.onBeforeSwap.selector,
                PoolSwapParams({
                    kind: SwapKind.EXACT_IN,
                    amountGivenScaled18: _swapAmount,
                    balancesScaled18: originalBalances,
                    indexIn: daiIdx,
                    indexOut: usdcIdx,
                    router: address(router),
                    userData: bytes("")
                }),
                pool
            )
        );

        vm.expectCall(
            pool,
            abi.encodeWithSelector(
                IBasePool.onSwap.selector,
                PoolSwapParams({
                    kind: SwapKind.EXACT_IN,
                    amountGivenScaled18: _swapAmount,
                    balancesScaled18: newBalances,
                    indexIn: daiIdx,
                    indexOut: usdcIdx,
                    router: address(router),
                    userData: bytes("")
                })
            )
        );

        router.swapSingleTokenExactIn(pool, dai, usdc, _swapAmount, 0, MAX_UINT256, false, bytes(""));
    }

    function testOnBeforeAddLiquidityHookAltersBalances() public {
        HooksConfig memory config = vault.getHooksConfig(pool);
        config.shouldCallBeforeAddLiquidity = true;
        vault.manualSetHooksConfig(pool, config);

        uint256[] memory originalBalances = [poolInitAmount, poolInitAmount].toMemoryArray();
        // `newBalances` are raw and scaled18, because rate is 1 and decimals are 18.
        uint256[] memory newBalances = [poolInitAmount / 2, poolInitAmount / 3].toMemoryArray();
        uint256[] memory amountsIn = [defaultAmount, defaultAmount].toMemoryArray();

        // Change balances of the pool on before hook.
        PoolHooksMock(poolHooksContract).setChangePoolBalancesOnBeforeAddLiquidityHook(true, newBalances);

        vm.prank(bob);
        // Check that balances were not changed before onBeforeHook.
        vm.expectCall(
            address(poolHooksContract),
            abi.encodeWithSelector(
                IHooks.onBeforeAddLiquidity.selector,
                router,
                pool,
                AddLiquidityKind.CUSTOM,
                amountsIn,
                bptAmountRoundDown,
                originalBalances,
                bytes("")
            )
        );

        vm.expectCall(
            pool,
            abi.encodeWithSelector(
                IPoolLiquidity.onAddLiquidityCustom.selector,
                router,
                amountsIn,
                bptAmountRoundDown,
                newBalances,
                bytes("")
            )
        );

        router.addLiquidityCustom(pool, amountsIn, bptAmountRoundDown, false, bytes(""));
    }

    function testOnBeforeRemoveLiquidityHookAlterBalance() public {
        HooksConfig memory config = vault.getHooksConfig(pool);
        config.shouldCallBeforeRemoveLiquidity = true;
        vault.manualSetHooksConfig(pool, config);

        uint256[] memory amountsOut = [defaultAmount, defaultAmount].toMemoryArray();

        vm.prank(alice);
        // Add liquidity to have BPTs to remove liquidity later.
        router.addLiquidityUnbalanced(pool, amountsOut, 0, false, bytes(""));

        uint256 balanceAfterLiquidity = poolInitAmount + defaultAmount;

        uint256[] memory originalBalances = [balanceAfterLiquidity, balanceAfterLiquidity].toMemoryArray();
        // We set balances to something related to balanceAfterLiquidity because bptAmountsOut is simpler to calculate.
        // `newBalances` are raw and scaled18, because rate is 1 and decimals are 18.
        uint256[] memory newBalances = [2 * balanceAfterLiquidity, 3 * balanceAfterLiquidity].toMemoryArray();

        // Change balances of the pool on before hook.
        PoolHooksMock(poolHooksContract).setChangePoolBalancesOnBeforeRemoveLiquidityHook(true, newBalances);

        // Check if balances were not changed before onBeforeHook.
        vm.expectCall(
            address(poolHooksContract),
            abi.encodeWithSelector(
                IHooks.onBeforeRemoveLiquidity.selector,
                router,
                pool,
                RemoveLiquidityKind.CUSTOM,
                bptAmount,
                amountsOut,
                originalBalances,
                bytes("")
            )
        );

        // removeLiquidityCustom passes the minAmountsOut to the callback, so we can check that they are updated.
        vm.expectCall(
            pool,
            abi.encodeWithSelector(
                IPoolLiquidity.onRemoveLiquidityCustom.selector,
                router,
                bptAmount,
                amountsOut,
                newBalances,
                bytes("")
            )
        );
        vm.prank(alice);
        router.removeLiquidityCustom(pool, bptAmount, amountsOut, false, bytes(""));
    }
}
