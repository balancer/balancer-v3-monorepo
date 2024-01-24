// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IPoolCallbacks } from "@balancer-labs/v3-interfaces/contracts/vault/IPoolCallbacks.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";

import { PoolMock } from "../../contracts/test/PoolMock.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract CallbacksTest is BaseVaultTest {
    using ArrayHelpers for *;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        PoolConfig memory config = vault.getPoolConfig(address(pool));
        config.callbacks.shouldCallBeforeSwap = true;
        config.callbacks.shouldCallAfterSwap = true;
        vault.setConfig(address(pool), config);
    }

    function testOnBeforeSwapCallback() public {
        vm.prank(bob);
        vm.expectCall(
            address(pool),
            abi.encodeWithSelector(
                IPoolCallbacks.onBeforeSwap.selector,
                IBasePool.SwapParams({
                    kind: SwapKind.GIVEN_IN,
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

    function testOnBeforeSwapCallbackRevert() public {
        // should fail
        PoolMock(pool).setFailOnBeforeSwapCallback(true);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.CallbackFailed.selector));
        router.swapExactIn(address(pool), usdc, dai, defaultAmount, defaultAmount, type(uint256).max, false, bytes(""));
    }

    function testOnAfterSwapCallback() public {
        vm.prank(bob);
        vm.expectCall(
            address(pool),
            abi.encodeWithSelector(
                IBasePool.onSwap.selector,
                IBasePool.SwapParams({
                    kind: SwapKind.GIVEN_IN,
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

    function testOnAfterSwapCallbackRevert() public {
        // should fail
        PoolMock(pool).setFailOnAfterSwapCallback(true);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.CallbackFailed.selector));
        router.swapExactIn(address(pool), usdc, dai, defaultAmount, defaultAmount, type(uint256).max, false, bytes(""));
    }

    // Before add

    function testOnBeforeAddLiquidityFlag() public {
        PoolMock(pool).setFailOnBeforeAddLiquidityCallback(true);

        vm.prank(bob);
        // Doesn't fail, does not call callbacks
        router.addLiquidityUnbalanced(
            address(pool),
            [defaultAmount, defaultAmount].toMemoryArray(),
            bptAmount,
            false,
            bytes("")
        );
    }

    function testOnBeforeAddLiquidityCallback() public {
        PoolConfig memory config = vault.getPoolConfig(address(pool));
        config.callbacks.shouldCallBeforeAddLiquidity = true;
        vault.setConfig(address(pool), config);

        vm.prank(bob);
        vm.expectCall(
            address(pool),
            abi.encodeWithSelector(
                IPoolCallbacks.onBeforeAddLiquidity.selector,
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
        PoolMock(pool).setFailOnBeforeRemoveLiquidityCallback(true);

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

    function testOnBeforeRemoveLiquidityCallback() public {
        PoolConfig memory config = vault.getPoolConfig(address(pool));
        config.callbacks.shouldCallBeforeRemoveLiquidity = true;
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
                IPoolCallbacks.onBeforeRemoveLiquidity.selector,
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
        PoolMock(pool).setFailOnAfterAddLiquidityCallback(true);

        vm.prank(bob);
        // Doesn't fail, does not call callbacks
        router.addLiquidityUnbalanced(
            address(pool),
            [defaultAmount, defaultAmount].toMemoryArray(),
            bptAmount,
            false,
            bytes("")
        );
    }

    function testOnAfterAddLiquidityCallback() public {
        PoolConfig memory config = vault.getPoolConfig(address(pool));
        config.callbacks.shouldCallAfterAddLiquidity = true;
        vault.setConfig(address(pool), config);

        vm.prank(bob);
        vm.expectCall(
            address(pool),
            abi.encodeWithSelector(
                IPoolCallbacks.onAfterAddLiquidity.selector,
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
        PoolMock(pool).setFailOnAfterRemoveLiquidityCallback(true);

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

    function testOnAfterRemoveLiquidityCallback() public {
        PoolConfig memory config = vault.getPoolConfig(address(pool));
        config.callbacks.shouldCallAfterRemoveLiquidity = true;
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
                IPoolCallbacks.onAfterRemoveLiquidity.selector,
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
