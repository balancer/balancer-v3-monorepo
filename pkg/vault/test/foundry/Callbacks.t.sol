// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IPoolHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IPoolHooks.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";

import { PoolMock } from "../../contracts/test/PoolMock.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract HooksTest is BaseVaultTest {
    using ArrayHelpers for *;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        PoolConfig memory config = vault.getPoolConfig(address(pool));
        config.hooks.shouldCallBeforeSwap = true;
        config.hooks.shouldCallAfterSwap = true;
        vault.setConfig(address(pool), config);
    }

    function testOnBeforeSwapHook() public {
        vm.prank(bob);
        vm.expectCall(
            address(pool),
            abi.encodeWithSelector(
                IPoolHooks.onBeforeSwap.selector,
                IBasePool.SwapParams({
                    kind: SwapKind.EXACT_IN,
                    amountGivenScaled18: defaultAmount,
                    balancesScaled18: [defaultAmount, defaultAmount].toMemoryArray(),
                    indexIn: 1,
                    indexOut: 0,
                    sender: address(router),
                    userData: bytes("")
                })
            )
        );
        router.swapExactIn(address(pool), usdc, dai, defaultAmount, 0, type(uint256).max, false, bytes(""));
    }

    function testOnBeforeSwapHookRevert() public {
        // should fail
        PoolMock(pool).setFailOnBeforeSwapHook(true);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.HookFailed.selector));
        router.swapExactIn(address(pool), usdc, dai, defaultAmount, defaultAmount, type(uint256).max, false, bytes(""));
    }

    function testOnAfterSwapHook() public {
        vm.prank(bob);
        vm.expectCall(
            address(pool),
            abi.encodeWithSelector(
                IBasePool.onSwap.selector,
                IBasePool.SwapParams({
                    kind: SwapKind.EXACT_IN,
                    amountGivenScaled18: defaultAmount,
                    balancesScaled18: [defaultAmount, defaultAmount].toMemoryArray(),
                    indexIn: 1,
                    indexOut: 0,
                    sender: address(router),
                    userData: bytes("")
                })
            )
        );
        router.swapExactIn(address(pool), usdc, dai, defaultAmount, 0, type(uint256).max, false, bytes(""));
    }

    function testOnAfterSwapHookRevert() public {
        // should fail
        PoolMock(pool).setFailOnAfterSwapHook(true);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.HookFailed.selector));
        router.swapExactIn(address(pool), usdc, dai, defaultAmount, defaultAmount, type(uint256).max, false, bytes(""));
    }

    // Before add

    function testOnBeforeAddLiquidityFlag() public {
        PoolMock(pool).setFailOnBeforeAddLiquidityHook(true);

        vm.prank(bob);
        // Doesn't fail, does not call hooks
        router.addLiquidityUnbalanced(
            address(pool),
            [defaultAmount, defaultAmount].toMemoryArray(),
            bptAmount,
            false,
            bytes("")
        );
    }

    function testOnBeforeAddLiquidityHook() public {
        PoolConfig memory config = vault.getPoolConfig(address(pool));
        config.hooks.shouldCallBeforeAddLiquidity = true;
        vault.setConfig(address(pool), config);

        vm.prank(bob);
        vm.expectCall(
            address(pool),
            abi.encodeWithSelector(
                IPoolHooks.onBeforeAddLiquidity.selector,
                bob,
                AddLiquidityKind.UNBALANCED,
                [defaultAmount, defaultAmount].toMemoryArray(),
                bptAmountRoundDown,
                [defaultAmount, defaultAmount].toMemoryArray(),
                bytes("")
            )
        );
        router.addLiquidityUnbalanced(
            address(pool),
            [defaultAmount, defaultAmount].toMemoryArray(),
            bptAmountRoundDown,
            false,
            bytes("")
        );
    }

    // Before remove

    function testOnBeforeRemoveLiquidityFlag() public {
        PoolMock(pool).setFailOnBeforeRemoveLiquidityHook(true);

        vm.prank(alice);
        router.addLiquidityUnbalanced(
            address(pool),
            [defaultAmount, defaultAmount].toMemoryArray(),
            bptAmount,
            false,
            bytes("")
        );

        vm.prank(alice);
        router.removeLiquidityProportional(
            address(pool),
            bptAmount,
            [defaultAmountRoundDown, defaultAmountRoundDown].toMemoryArray(),
            false,
            bytes("")
        );
    }

    function testOnBeforeRemoveLiquidityHook() public {
        PoolConfig memory config = vault.getPoolConfig(address(pool));
        config.hooks.shouldCallBeforeRemoveLiquidity = true;
        vault.setConfig(address(pool), config);

        vm.prank(alice);
        router.addLiquidityUnbalanced(
            address(pool),
            [defaultAmount, defaultAmount].toMemoryArray(),
            bptAmount,
            false,
            bytes("")
        );

        vm.expectCall(
            address(pool),
            abi.encodeWithSelector(
                IPoolHooks.onBeforeRemoveLiquidity.selector,
                alice,
                RemoveLiquidityKind.PROPORTIONAL,
                bptAmount,
                [defaultAmountRoundDown, defaultAmountRoundDown].toMemoryArray(),
                [2 * defaultAmount, 2 * defaultAmount].toMemoryArray(),
                bytes("")
            )
        );
        vm.prank(alice);
        router.removeLiquidityProportional(
            address(pool),
            bptAmount,
            [defaultAmountRoundDown, defaultAmountRoundDown].toMemoryArray(),
            false,
            bytes("")
        );
    }

    // After add

    function testOnAfterAddLiquidityFlag() public {
        PoolMock(pool).setFailOnAfterAddLiquidityHook(true);

        vm.prank(bob);
        // Doesn't fail, does not call hooks
        router.addLiquidityUnbalanced(
            address(pool),
            [defaultAmount, defaultAmount].toMemoryArray(),
            bptAmount,
            false,
            bytes("")
        );
    }

    function testOnAfterAddLiquidityHook() public {
        PoolConfig memory config = vault.getPoolConfig(address(pool));
        config.hooks.shouldCallAfterAddLiquidity = true;
        vault.setConfig(address(pool), config);

        vm.prank(bob);
        vm.expectCall(
            address(pool),
            abi.encodeWithSelector(
                IPoolHooks.onAfterAddLiquidity.selector,
                bob,
                [defaultAmount, defaultAmount].toMemoryArray(),
                bptAmount,
                [2 * defaultAmount, 2 * defaultAmount].toMemoryArray(),
                bytes("")
            )
        );
        router.addLiquidityUnbalanced(
            address(pool),
            [defaultAmount, defaultAmount].toMemoryArray(),
            bptAmountRoundDown,
            false,
            bytes("")
        );
    }

    // After remove

    function testOnAfterRemoveLiquidityFlag() public {
        PoolMock(pool).setFailOnAfterRemoveLiquidityHook(true);

        vm.prank(alice);
        router.addLiquidityUnbalanced(
            address(pool),
            [defaultAmount, defaultAmount].toMemoryArray(),
            bptAmount,
            false,
            bytes("")
        );

        vm.prank(alice);
        router.removeLiquidityProportional(
            address(pool),
            bptAmount,
            [defaultAmountRoundDown, defaultAmountRoundDown].toMemoryArray(),
            false,
            bytes("")
        );
    }

    function testOnAfterRemoveLiquidityHook() public {
        PoolConfig memory config = vault.getPoolConfig(address(pool));
        config.hooks.shouldCallAfterRemoveLiquidity = true;
        vault.setConfig(address(pool), config);

        vm.prank(alice);
        router.addLiquidityUnbalanced(
            address(pool),
            [defaultAmount, defaultAmount].toMemoryArray(),
            bptAmount,
            false,
            bytes("")
        );

        vm.expectCall(
            address(pool),
            abi.encodeWithSelector(
                IPoolHooks.onAfterRemoveLiquidity.selector,
                alice,
                bptAmount,
                [defaultAmount, defaultAmount].toMemoryArray(),
                [defaultAmount, defaultAmount].toMemoryArray(),
                bytes("")
            )
        );

        vm.prank(alice);
        router.removeLiquidityProportional(
            address(pool),
            bptAmount,
            [defaultAmountRoundDown, defaultAmountRoundDown].toMemoryArray(),
            false,
            bytes("")
        );
    }
}
