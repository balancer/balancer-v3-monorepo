// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { PoolMock } from "../../contracts/test/PoolMock.sol";
import { PoolFactoryMock } from "../../contracts/test/PoolFactoryMock.sol";
import { PoolHooksMock } from "../../contracts/test/PoolHooksMock.sol";
import { PoolConfigBits } from "../../contracts/lib/PoolConfigLib.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract HooksTest is BaseVaultTest {
    using ArrayHelpers for *;
    using FixedPoint for uint256;

    uint256 internal daiIdx;
    uint256 internal usdcIdx;

    // Another factory and pool to test hook onRegister
    PoolFactoryMock internal anotherFactory;
    address internal anotherPool;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        // Sets the pool address in the hook, so we can check balances of the pool inside the hook
        PoolHooksMock(poolHooksContract).setPool(address(pool));

        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));

        // Create another pool and pool factory to test onRegister
        uint256 pauseWindowEndTime = vault.getPauseWindowEndTime();
        uint256 bufferPeriodDuration = vault.getBufferPeriodDuration();
        anotherFactory = new PoolFactoryMock(IVault(vault), pauseWindowEndTime - bufferPeriodDuration);
        vm.label(address(anotherFactory), "another factory");
        anotherPool = address(new PoolMock(IVault(address(vault)), "Another Pool", "ANOTHER"));
        vm.label(address(anotherPool), "another pool");
    }

    function createHook() internal override returns (address) {
        PoolHookFlags memory poolHookFlags;
        poolHookFlags.shouldCallComputeDynamicSwapFee = true;
        poolHookFlags.shouldCallBeforeSwap = true;
        poolHookFlags.shouldCallAfterSwap = true;

        // Sets all flags as false
        return _createHook(poolHookFlags);
    }

    // TODO register
    function testOnRegisterWithFalseHookFlags() public {
        // disables all hooks by setting flags to false
        PoolHookFlags memory poolHookFlags;
        PoolHooksMock(poolHooksContract).setPoolHookFlags(poolHookFlags);

        // should not fail, since hooks are false
        _registerAnotherPool();
    }

    function testOnRegisterNotAllowedFactory() public {
        PoolHookFlags memory poolHookFlags;
        // any flag, just to trigger hook onRegister
        poolHookFlags.shouldCallBeforeAddLiquidity = true;
        PoolHooksMock(poolHooksContract).setPoolHookFlags(poolHookFlags);

        vm.expectRevert(
            abi.encodeWithSelector(
                IVaultErrors.HookRegisterFailed.selector,
                address(poolHooksContract),
                address(anotherFactory)
            )
        );
        _registerAnotherPool();
    }

    // - can register if hook allows factory
    // - fail to register if hook flag is true but hook contract is address 0

    // dynamic fee

    function testOnComputeDynamicSwapFeeHook() public {
        vm.prank(bob);
        vm.expectCall(
            address(poolHooksContract),
            abi.encodeWithSelector(
                IHooks.onComputeDynamicSwapFee.selector,
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
        router.swapSingleTokenExactIn(address(pool), usdc, dai, defaultAmount, 0, MAX_UINT256, false, bytes(""));
    }

    function testOnComputeDynamicSwapFeeHookRevert() public {
        // should fail
        PoolHooksMock(poolHooksContract).setFailOnComputeDynamicSwapFeeHook(true);
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
        vm.prank(bob);
        vm.expectCall(
            address(poolHooksContract),
            abi.encodeWithSelector(
                IHooks.onBeforeSwap.selector,
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
        router.swapSingleTokenExactIn(address(pool), usdc, dai, defaultAmount, 0, MAX_UINT256, false, bytes(""));
    }

    function testOnBeforeSwapHookRevert() public {
        // should fail
        PoolHooksMock(poolHooksContract).setFailOnBeforeSwapHook(true);
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
        setSwapFeePercentage(swapFeePercentage);
        setProtocolSwapFeePercentage(protocolSwapFeePercentage);
        PoolHooksMock(poolHooksContract).setDynamicSwapFeePercentage(swapFeePercentage);

        uint256 expectedAmountOut = defaultAmount.mulDown(swapFeePercentage.complement());
        uint256 swapFee = defaultAmount.mulDown(swapFeePercentage);
        uint256 protocolFee = swapFee.mulDown(protocolSwapFeePercentage);

        vm.prank(bob);
        vm.expectCall(
            address(poolHooksContract),
            abi.encodeWithSelector(
                IHooks.onAfterSwap.selector,
                IHooks.AfterSwapParams({
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

        router.swapSingleTokenExactIn(address(pool), usdc, dai, defaultAmount, 0, MAX_UINT256, false, bytes(""));
    }

    function testOnAfterSwapHookRevert() public {
        // should fail
        PoolHooksMock(poolHooksContract).setFailOnAfterSwapHook(true);
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
        PoolHooksMock(poolHooksContract).setFailOnBeforeAddLiquidityHook(true);

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
            address(poolHooksContract),
            abi.encodeWithSelector(
                IHooks.onBeforeAddLiquidity.selector,
                router,
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
        PoolHooksMock(poolHooksContract).setFailOnBeforeRemoveLiquidityHook(true);

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
            address(poolHooksContract),
            abi.encodeWithSelector(
                IHooks.onBeforeRemoveLiquidity.selector,
                router,
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
        PoolHooksMock(poolHooksContract).setFailOnAfterAddLiquidityHook(true);

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
            address(poolHooksContract),
            abi.encodeWithSelector(
                IHooks.onAfterAddLiquidity.selector,
                router,
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
        PoolHooksMock(poolHooksContract).setFailOnAfterRemoveLiquidityHook(true);

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
            address(poolHooksContract),
            abi.encodeWithSelector(
                IHooks.onAfterRemoveLiquidity.selector,
                router,
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

    //    // utils
    function _registerAnotherPool() private {
        anotherFactory.registerPool(
            address(anotherPool),
            vault.buildTokenConfig([address(dai), address(usdc)].toMemoryArray().asIERC20()),
            PoolRoleAccounts({ pauseManager: address(0), swapFeeManager: address(0), poolCreator: address(0) }),
            poolHooksContract,
            LiquidityManagement({
                disableUnbalancedLiquidity: false,
                enableAddLiquidityCustom: true,
                enableRemoveLiquidityCustom: true
            })
        );
    }
}
