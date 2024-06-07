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
        uint32 pauseWindowEndTime = vault.getPauseWindowEndTime();
        uint32 bufferPeriodDuration = vault.getBufferPeriodDuration();
        anotherFactory = new PoolFactoryMock(IVault(vault), pauseWindowEndTime - bufferPeriodDuration);
        vm.label(address(anotherFactory), "another factory");
        anotherPool = address(new PoolMock(IVault(address(vault)), "Another Pool", "ANOTHER"));
        vm.label(address(anotherPool), "another pool");
    }

    function createHook() internal override returns (address) {
        IHooks.HookFlags memory hookFlags;
        return _createHook(hookFlags);
    }

    // onRegister

    function testOnRegisterNotAllowedFactory() public {
        PoolRoleAccounts memory roleAccounts;

        TokenConfig[] memory tokenConfig = vault.buildTokenConfig(
            [address(dai), address(usdc)].toMemoryArray().asIERC20()
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IVaultErrors.HookRegistrationFailed.selector,
                poolHooksContract,
                address(anotherPool),
                address(anotherFactory)
            )
        );
        anotherFactory.registerPool(
            address(anotherPool),
            tokenConfig,
            roleAccounts,
            poolHooksContract,
            LiquidityManagement({
                disableUnbalancedLiquidity: false,
                enableAddLiquidityCustom: true,
                enableRemoveLiquidityCustom: true
            })
        );
    }

    function testOnRegisterAllowedFactory() public {
        PoolRoleAccounts memory roleAccounts;
        LiquidityManagement memory liquidityManagement = LiquidityManagement({
            disableUnbalancedLiquidity: false,
            enableAddLiquidityCustom: false,
            enableRemoveLiquidityCustom: false
        });

        // Should succeed, since factory is allowed in the poolHooksContract
        PoolHooksMock(poolHooksContract).allowFactory(address(anotherFactory));

        TokenConfig[] memory tokenConfig = vault.buildTokenConfig(
            [address(dai), address(usdc)].toMemoryArray().asIERC20()
        );

        vm.expectCall(
            address(poolHooksContract),
            abi.encodeWithSelector(
                IHooks.onRegister.selector,
                address(anotherFactory),
                address(anotherPool),
                tokenConfig,
                liquidityManagement
            )
        );

        anotherFactory.registerPool(
            address(anotherPool),
            tokenConfig,
            roleAccounts,
            poolHooksContract,
            liquidityManagement
        );
    }

    // dynamic fee

    function testOnComputeDynamicSwapFeeHook() public {
        HooksConfig memory hooksConfig = vault.getHooksConfig(address(pool));
        hooksConfig.shouldCallComputeDynamicSwapFee = true;
        vault.setHooksConfig(address(pool), hooksConfig);

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
        snapStart("swapWithOnComputeDynamicSwapFeeHook");
        router.swapSingleTokenExactIn(address(pool), usdc, dai, defaultAmount, 0, MAX_UINT256, false, bytes(""));
        snapEnd();
    }

    function testOnComputeDynamicSwapFeeHookRevert() public {
        HooksConfig memory hooksConfig = vault.getHooksConfig(address(pool));
        hooksConfig.shouldCallComputeDynamicSwapFee = true;
        vault.setHooksConfig(address(pool), hooksConfig);

        // should fail
        PoolHooksMock(poolHooksContract).setFailOnComputeDynamicSwapFeeHook(true);
        vm.prank(bob);
        vm.expectRevert(IVaultErrors.DynamicSwapFeeHookFailed.selector);
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
        HooksConfig memory hooksConfig = vault.getHooksConfig(address(pool));
        hooksConfig.shouldCallBeforeSwap = true;
        vault.setHooksConfig(address(pool), hooksConfig);

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
                }),
                pool
            )
        );
        snapStart("swapWithOnBeforeSwapHook");
        router.swapSingleTokenExactIn(address(pool), usdc, dai, defaultAmount, 0, MAX_UINT256, false, bytes(""));
        snapEnd();
    }

    function testOnBeforeSwapHookRevert() public {
        HooksConfig memory hooksConfig = vault.getHooksConfig(address(pool));
        hooksConfig.shouldCallBeforeSwap = true;
        vault.setHooksConfig(address(pool), hooksConfig);

        // should fail
        PoolHooksMock(poolHooksContract).setFailOnBeforeSwapHook(true);
        vm.prank(bob);
        vm.expectRevert(IVaultErrors.BeforeSwapHookFailed.selector);
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
        HooksConfig memory hooksConfig = vault.getHooksConfig(address(pool));
        hooksConfig.shouldCallAfterSwap = true;
        vault.setHooksConfig(address(pool), hooksConfig);

        setSwapFeePercentage(swapFeePercentage);
        vault.manualSetAggregateProtocolSwapFeePercentage(
            pool,
            _getAggregateFeePercentage(protocolSwapFeePercentage, 0)
        );
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
                    amountCalculatedScaled18: expectedAmountOut,
                    amountCalculatedRaw: expectedAmountOut,
                    router: address(router),
                    pool: pool,
                    userData: ""
                })
            )
        );

        snapStart("swapWithOnAfterSwapHook");
        router.swapSingleTokenExactIn(address(pool), usdc, dai, defaultAmount, 0, MAX_UINT256, false, bytes(""));
        snapEnd();
    }

    function testOnAfterSwapHookRevert() public {
        HooksConfig memory hooksConfig = vault.getHooksConfig(address(pool));
        hooksConfig.shouldCallAfterSwap = true;
        vault.setHooksConfig(address(pool), hooksConfig);

        // should fail
        PoolHooksMock(poolHooksContract).setFailOnAfterSwapHook(true);
        vm.prank(bob);
        vm.expectRevert(IVaultErrors.AfterSwapHookFailed.selector);
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
        HooksConfig memory hooksConfig = vault.getHooksConfig(address(pool));
        hooksConfig.shouldCallBeforeAddLiquidity = true;
        vault.setHooksConfig(address(pool), hooksConfig);

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
        HooksConfig memory hooksConfig = vault.getHooksConfig(address(pool));
        hooksConfig.shouldCallBeforeRemoveLiquidity = true;
        vault.setHooksConfig(address(pool), hooksConfig);

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
        HooksConfig memory hooksConfig = vault.getHooksConfig(address(pool));
        hooksConfig.shouldCallAfterAddLiquidity = true;
        vault.setHooksConfig(address(pool), hooksConfig);

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
        HooksConfig memory hooksConfig = vault.getHooksConfig(address(pool));
        hooksConfig.shouldCallAfterRemoveLiquidity = true;
        vault.setHooksConfig(address(pool), hooksConfig);

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
}
