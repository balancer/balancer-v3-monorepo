// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IPoolHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IPoolHooks.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { PoolMock } from "../../contracts/test/PoolMock.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract HooksTest is BaseVaultTest {
    using ArrayHelpers for *;
    using FixedPoint for uint256;

    uint256 internal daiIdx;
    uint256 internal usdcIdx;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));
    }

    // dynamic fee

    function testOnComputeDynamicSwapFeeHook() public {
        PoolHooks memory poolHookFlags = vault.getPoolConfig(address(pool)).hooks;
        poolHookFlags.shouldCallComputeDynamicSwapFee = true;
        _changePoolHooksConfig(poolHookFlags);

        vm.prank(bob);
        vm.expectCall(
            address(pool),
            abi.encodeWithSelector(
                IPoolHooks.onComputeDynamicSwapFee.selector,
                IBasePool.PoolSwapParams({
                    kind: SwapKind.EXACT_IN,
                    amountGivenScaled18: defaultAmount,
                    balancesScaled18: [defaultAmount, defaultAmount].toMemoryArray(),
                    indexIn: usdcIdx,
                    indexOut: daiIdx,
                    router: address(router),
                    userData: bytes("")
                })
            )
        );
        snapStart("swapWithOnComputeDynamicSwapFeeHook");
        router.swapSingleTokenExactIn(address(pool), usdc, dai, defaultAmount, 0, MAX_UINT256, false, bytes(""));
        snapEnd();
    }

    function testOnComputeDynamicSwapFeeHookRevert() public {
        PoolHooks memory poolHookFlags = vault.getPoolConfig(address(pool)).hooks;
        poolHookFlags.shouldCallComputeDynamicSwapFee = true;
        _changePoolHooksConfig(poolHookFlags);

        // should fail
        PoolMock(pool).setFailComputeDynamicSwapFeeHook(true);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.DynamicSwapFeeHookFailed.selector));
        router.swapSingleTokenExactIn(
            address(pool),
            usdc,
            dai,
            defaultAmount,
            defaultAmount,
            MAX_UINT256,
            false,
            bytes("")
        );
    }

    // before swap

    function testOnBeforeSwapHook() public {
        PoolHooks memory poolHookFlags = vault.getPoolConfig(address(pool)).hooks;
        poolHookFlags.shouldCallBeforeSwap = true;
        _changePoolHooksConfig(poolHookFlags);

        vm.prank(bob);
        vm.expectCall(
            address(pool),
            abi.encodeWithSelector(
                IPoolHooks.onBeforeSwap.selector,
                IBasePool.PoolSwapParams({
                    kind: SwapKind.EXACT_IN,
                    amountGivenScaled18: defaultAmount,
                    balancesScaled18: [defaultAmount, defaultAmount].toMemoryArray(),
                    indexIn: usdcIdx,
                    indexOut: daiIdx,
                    router: address(router),
                    userData: bytes("")
                })
            )
        );
        snapStart("swapWithOnBeforeSwapHook");
        router.swapSingleTokenExactIn(address(pool), usdc, dai, defaultAmount, 0, MAX_UINT256, false, bytes(""));
        snapEnd();
    }

    function testOnBeforeSwapHookRevert() public {
        PoolHooks memory poolHookFlags = vault.getPoolConfig(address(pool)).hooks;
        poolHookFlags.shouldCallBeforeSwap = true;
        _changePoolHooksConfig(poolHookFlags);

        // should fail
        PoolMock(pool).setFailOnBeforeSwapHook(true);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.BeforeSwapHookFailed.selector));
        router.swapSingleTokenExactIn(
            address(pool),
            usdc,
            dai,
            defaultAmount,
            defaultAmount,
            MAX_UINT256,
            false,
            bytes("")
        );
    }

    // after swap

    function testOnAfterSwapHook() public {
        PoolHooks memory poolHookFlags = vault.getPoolConfig(address(pool)).hooks;
        poolHookFlags.shouldCallAfterSwap = true;
        _changePoolHooksConfig(poolHookFlags);

        setSwapFeePercentage(swapFeePercentage);
        setProtocolSwapFeePercentage(protocolSwapFeePercentage);
        PoolMock(pool).setDynamicSwapFeePercentage(swapFeePercentage);

        uint256 expectedAmountOut = defaultAmount.mulDown(swapFeePercentage.complement());
        uint256 swapFee = defaultAmount.mulDown(swapFeePercentage);
        uint256 protocolFee = swapFee.mulDown(protocolSwapFeePercentage);

        vm.prank(bob);
        vm.expectCall(
            address(pool),
            abi.encodeWithSelector(
                IPoolHooks.onAfterSwap.selector,
                IPoolHooks.AfterSwapParams({
                    kind: SwapKind.EXACT_IN,
                    tokenIn: usdc,
                    tokenOut: dai,
                    amountInScaled18: defaultAmount,
                    amountOutScaled18: expectedAmountOut,
                    tokenInBalanceScaled18: defaultAmount * 2,
                    tokenOutBalanceScaled18: defaultAmount - expectedAmountOut - protocolFee,
                    router: address(router),
                    userData: ""
                }),
                expectedAmountOut
            )
        );

        snapStart("swapWithOnAfterSwapHook");
        router.swapSingleTokenExactIn(address(pool), usdc, dai, defaultAmount, 0, MAX_UINT256, false, bytes(""));
        snapEnd();
    }

    function testOnAfterSwapHookRevert() public {
        PoolHooks memory poolHookFlags = vault.getPoolConfig(address(pool)).hooks;
        poolHookFlags.shouldCallAfterSwap = true;
        _changePoolHooksConfig(poolHookFlags);

        // should fail
        PoolMock(pool).setFailOnAfterSwapHook(true);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.AfterSwapHookFailed.selector));
        router.swapSingleTokenExactIn(
            address(pool),
            usdc,
            dai,
            defaultAmount,
            defaultAmount,
            MAX_UINT256,
            false,
            bytes("")
        );
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
        PoolHooks memory poolHookFlags = vault.getPoolConfig(address(pool)).hooks;
        poolHookFlags.shouldCallBeforeAddLiquidity = true;
        _changePoolHooksConfig(poolHookFlags);

        vm.prank(bob);
        vm.expectCall(
            address(pool),
            abi.encodeWithSelector(
                IPoolHooks.onBeforeAddLiquidity.selector,
                router,
                AddLiquidityKind.UNBALANCED,
                [defaultAmount, defaultAmount].toMemoryArray(),
                bptAmountRoundDown,
                [defaultAmount, defaultAmount].toMemoryArray(),
                bytes("")
            )
        );
        snapStart("addLiquidityWithOnBeforeHook");
        router.addLiquidityUnbalanced(
            address(pool),
            [defaultAmount, defaultAmount].toMemoryArray(),
            bptAmountRoundDown,
            false,
            bytes("")
        );
        snapEnd();
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
        PoolHooks memory poolHookFlags = vault.getPoolConfig(address(pool)).hooks;
        poolHookFlags.shouldCallBeforeRemoveLiquidity = true;
        _changePoolHooksConfig(poolHookFlags);

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
                router,
                RemoveLiquidityKind.PROPORTIONAL,
                bptAmount,
                [defaultAmountRoundDown, defaultAmountRoundDown].toMemoryArray(),
                [2 * defaultAmount, 2 * defaultAmount].toMemoryArray(),
                bytes("")
            )
        );
        vm.prank(alice);
        snapStart("removeLiquidityWithOnBeforeHook");
        router.removeLiquidityProportional(
            address(pool),
            bptAmount,
            [defaultAmountRoundDown, defaultAmountRoundDown].toMemoryArray(),
            false,
            bytes("")
        );
        snapEnd();
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
        PoolHooks memory poolHookFlags = vault.getPoolConfig(address(pool)).hooks;
        poolHookFlags.shouldCallAfterAddLiquidity = true;
        _changePoolHooksConfig(poolHookFlags);

        vm.prank(bob);
        vm.expectCall(
            address(pool),
            abi.encodeWithSelector(
                IPoolHooks.onAfterAddLiquidity.selector,
                router,
                [defaultAmount, defaultAmount].toMemoryArray(),
                bptAmount,
                [2 * defaultAmount, 2 * defaultAmount].toMemoryArray(),
                bytes("")
            )
        );
        snapStart("addLiquidityWithOnAfterHook");
        router.addLiquidityUnbalanced(
            address(pool),
            [defaultAmount, defaultAmount].toMemoryArray(),
            bptAmountRoundDown,
            false,
            bytes("")
        );
        snapEnd();
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
        PoolHooks memory poolHookFlags = vault.getPoolConfig(address(pool)).hooks;
        poolHookFlags.shouldCallAfterRemoveLiquidity = true;
        _changePoolHooksConfig(poolHookFlags);

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
                router,
                bptAmount,
                [defaultAmount, defaultAmount].toMemoryArray(),
                [defaultAmount, defaultAmount].toMemoryArray(),
                bytes("")
            )
        );

        vm.prank(alice);
        snapStart("removeLiquidityWithOnAfterHook");
        router.removeLiquidityProportional(
            address(pool),
            bptAmount,
            [defaultAmountRoundDown, defaultAmountRoundDown].toMemoryArray(),
            false,
            bytes("")
        );
        snapEnd();
    }

    function _changePoolHooksConfig(PoolHooks memory poolHookFlags) private {
        PoolConfig memory config = vault.getPoolConfig(address(pool));
        config.hooks = poolHookFlags;
        vault.setConfig(address(pool), config);
    }
}
