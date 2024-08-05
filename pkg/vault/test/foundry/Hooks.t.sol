// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";

import { PoolMock } from "../../contracts/test/PoolMock.sol";
import { PoolFactoryMock } from "../../contracts/test/PoolFactoryMock.sol";
import { PoolHooksMock } from "../../contracts/test/PoolHooksMock.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract HooksTest is BaseVaultTest {
    using CastingHelpers for address[];
    using FixedPoint for uint256;
    using ArrayHelpers for *;

    uint256 internal daiIdx;
    uint256 internal usdcIdx;

    // Another factory and pool to test hook onRegister.
    PoolFactoryMock internal anotherFactory;
    address internal anotherPool;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        // Sets the pool address in the hook, so we can check balances of the pool inside the hook.
        PoolHooksMock(poolHooksContract).setPool(pool);

        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));

        // Create another pool and pool factory to test onRegister.
        uint32 pauseWindowEndTime = vault.getPauseWindowEndTime();
        uint32 bufferPeriodDuration = vault.getBufferPeriodDuration();
        anotherFactory = new PoolFactoryMock(IVault(vault), pauseWindowEndTime - bufferPeriodDuration);
        vm.label(address(anotherFactory), "another factory");
        anotherPool = address(new PoolMock(IVault(address(vault)), "Another Pool", "ANOTHER"));
        vm.label(address(anotherPool), "another pool");
    }

    function createHook() internal override returns (address) {
        HookFlags memory hookFlags;
        return _createHook(hookFlags);
    }

    // onRegister

    function testOnRegisterNotAllowedFactory() public {
        PoolRoleAccounts memory roleAccounts;
        LiquidityManagement memory liquidityManagement;
        liquidityManagement.enableAddLiquidityCustom = true;
        liquidityManagement.enableRemoveLiquidityCustom = true;

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
            liquidityManagement
        );
    }

    function testOnRegisterAllowedFactory() public {
        PoolRoleAccounts memory roleAccounts;
        LiquidityManagement memory liquidityManagement;

        // Should succeed, since factory is allowed in the poolHooksContract.
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

    function testOnRegisterHookAdjustedWithUnbalancedLiquidity() public {
        PoolRoleAccounts memory roleAccounts;
        LiquidityManagement memory liquidityManagement;

        // Registers the factory, so the factory is not rejected by the hook.
        PoolHooksMock(poolHooksContract).allowFactory(address(anotherFactory));

        // Enable hook adjusted amounts in the hooks, so hooks can change the amount calculated of add/remove liquidity
        // and swap operations.
        HookFlags memory hookFlags;
        hookFlags.enableHookAdjustedAmounts = true;
        PoolHooksMock(poolHooksContract).setHookFlags(hookFlags);

        TokenConfig[] memory tokenConfig = vault.buildTokenConfig(
            [address(dai), address(usdc)].toMemoryArray().asIERC20()
        );

        // Register should fail, because `enableHookAdjustedAmounts` flag requires unbalanced liquidity to be disabled.
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
            liquidityManagement
        );
    }

    // dynamic fee

    function testOnComputeDynamicSwapFeeHook() public {
        HooksConfig memory hooksConfig = vault.getHooksConfig(pool);
        hooksConfig.shouldCallComputeDynamicSwapFee = true;
        vault.manualSetHooksConfig(pool, hooksConfig);

        vm.prank(bob);
        vm.expectCall(
            address(poolHooksContract),
            abi.encodeWithSelector(
                IHooks.onComputeDynamicSwapFeePercentage.selector,
                PoolSwapParams({
                    kind: SwapKind.EXACT_IN,
                    amountGivenScaled18: defaultAmount,
                    balancesScaled18: [defaultAmount, defaultAmount].toMemoryArray(),
                    indexIn: usdcIdx,
                    indexOut: daiIdx,
                    router: address(router),
                    userData: bytes("")
                }),
                pool,
                0
            )
        );
        router.swapSingleTokenExactIn(pool, usdc, dai, defaultAmount, 0, MAX_UINT256, false, bytes(""));
    }

    function testOnComputeDynamicSwapFeeHookReturningStaticFee() public {
        uint256 staticSwapFeePercentage = 10e16;

        HooksConfig memory hooksConfig = vault.getHooksConfig(pool);
        hooksConfig.shouldCallComputeDynamicSwapFee = true;
        vault.manualSetHooksConfig(pool, hooksConfig);

        authorizer.grantRole(vault.getActionId(IVaultAdmin.setStaticSwapFeePercentage.selector), alice);
        vm.prank(alice);
        vault.setStaticSwapFeePercentage(pool, staticSwapFeePercentage);

        vm.prank(bob);
        vm.expectCall(
            address(poolHooksContract),
            abi.encodeWithSelector(
                IHooks.onComputeDynamicSwapFeePercentage.selector,
                PoolSwapParams({
                    kind: SwapKind.EXACT_IN,
                    amountGivenScaled18: defaultAmount,
                    balancesScaled18: [defaultAmount, defaultAmount].toMemoryArray(),
                    indexIn: usdcIdx,
                    indexOut: daiIdx,
                    router: address(router),
                    userData: bytes("")
                }),
                pool,
                staticSwapFeePercentage
            )
        );
        router.swapSingleTokenExactIn(pool, usdc, dai, defaultAmount, 0, MAX_UINT256, false, bytes(""));
    }

    function testOnComputeDynamicSwapFeeHookRevert() public {
        HooksConfig memory hooksConfig = vault.getHooksConfig(pool);
        hooksConfig.shouldCallComputeDynamicSwapFee = true;
        vault.manualSetHooksConfig(pool, hooksConfig);

        // should fail
        PoolHooksMock(poolHooksContract).setFailOnComputeDynamicSwapFeeHook(true);
        vm.prank(bob);
        vm.expectRevert(IVaultErrors.DynamicSwapFeeHookFailed.selector);
        router.swapSingleTokenExactIn(pool, usdc, dai, defaultAmount, defaultAmount, MAX_UINT256, false, bytes(""));
    }

    // before swap

    function testOnBeforeSwapHook() public {
        HooksConfig memory hooksConfig = vault.getHooksConfig(pool);
        hooksConfig.shouldCallBeforeSwap = true;
        vault.manualSetHooksConfig(pool, hooksConfig);

        vm.prank(bob);
        vm.expectCall(
            address(poolHooksContract),
            abi.encodeWithSelector(
                IHooks.onBeforeSwap.selector,
                PoolSwapParams({
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
        router.swapSingleTokenExactIn(pool, usdc, dai, defaultAmount, 0, MAX_UINT256, false, bytes(""));
    }

    function testOnBeforeSwapHookRevert() public {
        HooksConfig memory hooksConfig = vault.getHooksConfig(pool);
        hooksConfig.shouldCallBeforeSwap = true;
        vault.manualSetHooksConfig(pool, hooksConfig);

        // should fail
        PoolHooksMock(poolHooksContract).setFailOnBeforeSwapHook(true);
        vm.prank(bob);
        vm.expectRevert(IVaultErrors.BeforeSwapHookFailed.selector);
        router.swapSingleTokenExactIn(pool, usdc, dai, defaultAmount, defaultAmount, MAX_UINT256, false, bytes(""));
    }

    // after swap

    function testOnAfterSwapHook() public {
        HooksConfig memory hooksConfig = vault.getHooksConfig(pool);
        hooksConfig.shouldCallAfterSwap = true;
        vault.manualSetHooksConfig(pool, hooksConfig);

        setSwapFeePercentage(swapFeePercentage);
        vault.manualSetAggregateSwapFeePercentage(pool, protocolSwapFeePercentage);
        PoolHooksMock(poolHooksContract).setDynamicSwapFeePercentage(swapFeePercentage);

        uint256 expectedAmountOut = defaultAmount.mulDown(swapFeePercentage.complement());
        uint256 swapFee = defaultAmount.mulDown(swapFeePercentage);
        uint256 protocolFee = swapFee.mulDown(protocolSwapFeePercentage);

        vm.prank(bob);
        vm.expectCall(
            address(poolHooksContract),
            abi.encodeWithSelector(
                IHooks.onAfterSwap.selector,
                AfterSwapParams({
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

        router.swapSingleTokenExactIn(pool, usdc, dai, defaultAmount, 0, MAX_UINT256, false, bytes(""));
    }

    function testOnAfterSwapHookRevert() public {
        HooksConfig memory hooksConfig = vault.getHooksConfig(pool);
        hooksConfig.shouldCallAfterSwap = true;
        vault.manualSetHooksConfig(pool, hooksConfig);

        // should fail
        PoolHooksMock(poolHooksContract).setFailOnAfterSwapHook(true);
        vm.prank(bob);
        vm.expectRevert(IVaultErrors.AfterSwapHookFailed.selector);
        router.swapSingleTokenExactIn(pool, usdc, dai, defaultAmount, defaultAmount, MAX_UINT256, false, bytes(""));
    }

    // Before add

    function testOnBeforeAddLiquidityFlag() public {
        PoolHooksMock(poolHooksContract).setFailOnBeforeAddLiquidityHook(true);

        vm.prank(bob);
        // Doesn't fail, does not call hooks
        router.addLiquidityUnbalanced(
            pool,
            [defaultAmount, defaultAmount].toMemoryArray(),
            bptAmount,
            false,
            bytes("")
        );
    }

    function testOnBeforeAddLiquidityHook() public {
        HooksConfig memory hooksConfig = vault.getHooksConfig(pool);
        hooksConfig.shouldCallBeforeAddLiquidity = true;
        vault.manualSetHooksConfig(pool, hooksConfig);

        vm.prank(bob);
        vm.expectCall(
            address(poolHooksContract),
            abi.encodeWithSelector(
                IHooks.onBeforeAddLiquidity.selector,
                router,
                pool,
                AddLiquidityKind.UNBALANCED,
                [defaultAmount, defaultAmount].toMemoryArray(),
                bptAmountRoundDown,
                [defaultAmount, defaultAmount].toMemoryArray(),
                bytes("")
            )
        );
        router.addLiquidityUnbalanced(
            pool,
            [defaultAmount, defaultAmount].toMemoryArray(),
            bptAmountRoundDown,
            false,
            bytes("")
        );
    }

    function testOnBeforeAddLiquidityHookRevert() public {
        HooksConfig memory hooksConfig = vault.getHooksConfig(pool);
        hooksConfig.shouldCallBeforeAddLiquidity = true;
        vault.manualSetHooksConfig(pool, hooksConfig);

        // Force failure on AfterRemoveLiquidityHook
        PoolHooksMock(poolHooksContract).setFailOnBeforeAddLiquidityHook(true);

        vm.prank(bob);
        vm.expectRevert(IVaultErrors.BeforeAddLiquidityHookFailed.selector);
        router.addLiquidityUnbalanced(
            pool,
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
            pool,
            [defaultAmount, defaultAmount].toMemoryArray(),
            bptAmount,
            false,
            bytes("")
        );

        vm.prank(alice);
        router.removeLiquidityProportional(
            pool,
            bptAmount,
            [defaultAmountRoundDown, defaultAmountRoundDown].toMemoryArray(),
            false,
            bytes("")
        );
    }

    function testOnBeforeRemoveLiquidityHook() public {
        HooksConfig memory hooksConfig = vault.getHooksConfig(pool);
        hooksConfig.shouldCallBeforeRemoveLiquidity = true;
        vault.manualSetHooksConfig(pool, hooksConfig);

        vm.prank(alice);
        router.addLiquidityUnbalanced(
            pool,
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
                pool,
                RemoveLiquidityKind.PROPORTIONAL,
                bptAmount,
                [defaultAmountRoundDown, defaultAmountRoundDown].toMemoryArray(),
                [2 * defaultAmount, 2 * defaultAmount].toMemoryArray(),
                bytes("")
            )
        );
        vm.prank(alice);
        router.removeLiquidityProportional(
            pool,
            bptAmount,
            [defaultAmountRoundDown, defaultAmountRoundDown].toMemoryArray(),
            false,
            bytes("")
        );
    }

    function testOnBeforeRemoveLiquidityHookRevert() public {
        HooksConfig memory hooksConfig = vault.getHooksConfig(pool);
        hooksConfig.shouldCallBeforeRemoveLiquidity = true;
        vault.manualSetHooksConfig(pool, hooksConfig);

        // Add liquidity first, so Alice can remove it later
        vm.prank(alice);
        router.addLiquidityUnbalanced(
            pool,
            [defaultAmount, defaultAmount].toMemoryArray(),
            bptAmount,
            false,
            bytes("")
        );

        // Force failure on AfterRemoveLiquidityHook
        PoolHooksMock(poolHooksContract).setFailOnBeforeRemoveLiquidityHook(true);

        vm.prank(alice);
        vm.expectRevert(IVaultErrors.BeforeRemoveLiquidityHookFailed.selector);
        router.removeLiquidityProportional(
            pool,
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
            pool,
            [defaultAmount, defaultAmount].toMemoryArray(),
            bptAmount,
            false,
            bytes("")
        );
    }

    function testOnAfterAddLiquidityHook() public {
        HooksConfig memory hooksConfig = vault.getHooksConfig(pool);
        hooksConfig.shouldCallAfterAddLiquidity = true;
        vault.manualSetHooksConfig(pool, hooksConfig);

        vm.prank(bob);
        vm.expectCall(
            address(poolHooksContract),
            abi.encodeWithSelector(
                IHooks.onAfterAddLiquidity.selector,
                router,
                pool,
                AddLiquidityKind.UNBALANCED,
                [defaultAmount, defaultAmount].toMemoryArray(),
                [defaultAmount, defaultAmount].toMemoryArray(),
                bptAmount,
                [2 * defaultAmount, 2 * defaultAmount].toMemoryArray(),
                bytes("")
            )
        );
        router.addLiquidityUnbalanced(
            pool,
            [defaultAmount, defaultAmount].toMemoryArray(),
            bptAmountRoundDown,
            false,
            bytes("")
        );
    }

    function testOnAfterAddLiquidityHookRevert() public {
        HooksConfig memory hooksConfig = vault.getHooksConfig(pool);
        hooksConfig.shouldCallAfterAddLiquidity = true;
        vault.manualSetHooksConfig(pool, hooksConfig);

        // Force failure on AfterRemoveLiquidityHook
        PoolHooksMock(poolHooksContract).setFailOnAfterAddLiquidityHook(true);

        vm.prank(bob);
        vm.expectRevert(IVaultErrors.AfterAddLiquidityHookFailed.selector);
        router.addLiquidityUnbalanced(
            pool,
            [defaultAmount, defaultAmount].toMemoryArray(),
            bptAmountRoundDown,
            false,
            bytes("")
        );
    }

    function testOnAfterAddLiquidityHookEmptyHookAdjustedAmounts() public {
        HooksConfig memory hooksConfig = vault.getHooksConfig(pool);
        hooksConfig.shouldCallAfterAddLiquidity = true;
        vault.manualSetHooksConfig(pool, hooksConfig);

        // Return empty hook adjusted amounts
        PoolHooksMock(poolHooksContract).enableForcedHookAdjustedAmountsLiquidity(new uint256[](0));

        vm.prank(bob);
        vm.expectRevert(IVaultErrors.AfterAddLiquidityHookFailed.selector);
        router.addLiquidityUnbalanced(
            pool,
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
            pool,
            [defaultAmount, defaultAmount].toMemoryArray(),
            bptAmount,
            false,
            bytes("")
        );

        vm.prank(alice);
        router.removeLiquidityProportional(
            pool,
            bptAmount,
            [defaultAmountRoundDown, defaultAmountRoundDown].toMemoryArray(),
            false,
            bytes("")
        );
    }

    function testOnAfterRemoveLiquidityHook() public {
        HooksConfig memory hooksConfig = vault.getHooksConfig(pool);
        hooksConfig.shouldCallAfterRemoveLiquidity = true;
        vault.manualSetHooksConfig(pool, hooksConfig);

        vm.prank(alice);
        router.addLiquidityUnbalanced(
            pool,
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
                pool,
                RemoveLiquidityKind.PROPORTIONAL,
                bptAmount,
                [defaultAmount, defaultAmount].toMemoryArray(),
                [defaultAmount, defaultAmount].toMemoryArray(),
                [defaultAmount, defaultAmount].toMemoryArray(),
                bytes("")
            )
        );

        vm.prank(alice);
        router.removeLiquidityProportional(
            pool,
            bptAmount,
            [defaultAmountRoundDown, defaultAmountRoundDown].toMemoryArray(),
            false,
            bytes("")
        );
    }

    function testOnAfterRemoveLiquidityHookRevert() public {
        HooksConfig memory hooksConfig = vault.getHooksConfig(pool);
        hooksConfig.shouldCallAfterRemoveLiquidity = true;
        vault.manualSetHooksConfig(pool, hooksConfig);

        // Add liquidity first, so Alice can remove it later.
        vm.prank(alice);
        router.addLiquidityUnbalanced(
            pool,
            [defaultAmount, defaultAmount].toMemoryArray(),
            bptAmount,
            false,
            bytes("")
        );

        // Force failure on AfterRemoveLiquidityHook.
        PoolHooksMock(poolHooksContract).setFailOnAfterRemoveLiquidityHook(true);

        vm.prank(alice);
        vm.expectRevert(IVaultErrors.AfterRemoveLiquidityHookFailed.selector);
        router.removeLiquidityProportional(
            pool,
            bptAmount,
            [defaultAmountRoundDown, defaultAmountRoundDown].toMemoryArray(),
            false,
            bytes("")
        );
    }

    function testOnAfterRemoveLiquidityHookEmptyHookAdjustedAmounts() public {
        HooksConfig memory hooksConfig = vault.getHooksConfig(pool);
        hooksConfig.shouldCallAfterRemoveLiquidity = true;
        vault.manualSetHooksConfig(pool, hooksConfig);

        // Add liquidity first, so Alice can remove it later.
        vm.prank(alice);
        router.addLiquidityUnbalanced(
            pool,
            [defaultAmount, defaultAmount].toMemoryArray(),
            bptAmount,
            false,
            bytes("")
        );

        // Return empty hook adjusted amounts.
        PoolHooksMock(poolHooksContract).enableForcedHookAdjustedAmountsLiquidity(new uint256[](0));

        vm.prank(alice);
        vm.expectRevert(IVaultErrors.AfterRemoveLiquidityHookFailed.selector);
        router.removeLiquidityProportional(
            pool,
            bptAmount,
            [defaultAmountRoundDown, defaultAmountRoundDown].toMemoryArray(),
            false,
            bytes("")
        );
    }
}
