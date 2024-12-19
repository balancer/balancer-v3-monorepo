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
        PoolHooksMock(poolHooksContract()).setPool(pool());

        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));

        // Create another pool and pool factory to test onRegister.
        uint32 pauseWindowEndTime = vault.getPauseWindowEndTime();
        uint32 bufferPeriodDuration = vault.getBufferPeriodDuration();
        anotherFactory = deployPoolFactoryMock(IVault(vault), pauseWindowEndTime - bufferPeriodDuration);
        vm.label(address(anotherFactory), "another factory");
        anotherPool = address(deployPoolMock(IVault(address(vault)), "Another Pool", "ANOTHER"));
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
                poolHooksContract(),
                address(anotherPool),
                address(anotherFactory)
            )
        );
        anotherFactory.registerPool(
            address(anotherPool),
            tokenConfig,
            roleAccounts,
            poolHooksContract(),
            liquidityManagement
        );
    }

    function testOnRegisterAllowedFactory() public {
        PoolRoleAccounts memory roleAccounts;
        LiquidityManagement memory liquidityManagement;

        // Should succeed, since factory is allowed in the poolHooksContract().
        PoolHooksMock(poolHooksContract()).allowFactory(address(anotherFactory));

        TokenConfig[] memory tokenConfig = vault.buildTokenConfig(
            [address(dai), address(usdc)].toMemoryArray().asIERC20()
        );

        vm.expectCall(
            address(poolHooksContract()),
            abi.encodeCall(
                IHooks.onRegister,
                (address(anotherFactory), address(anotherPool), tokenConfig, liquidityManagement)
            )
        );

        anotherFactory.registerPool(
            address(anotherPool),
            tokenConfig,
            roleAccounts,
            poolHooksContract(),
            liquidityManagement
        );
    }

    function testOnRegisterHookAdjustedWithUnbalancedLiquidity() public {
        PoolRoleAccounts memory roleAccounts;
        LiquidityManagement memory liquidityManagement;

        // Registers the factory, so the factory is not rejected by the hook.
        PoolHooksMock(poolHooksContract()).allowFactory(address(anotherFactory));

        // Enable hook adjusted amounts in the hooks, so hooks can change the amount calculated of add/remove liquidity
        // and swap operations.
        HookFlags memory hookFlags;
        hookFlags.enableHookAdjustedAmounts = true;
        PoolHooksMock(poolHooksContract()).setHookFlags(hookFlags);

        TokenConfig[] memory tokenConfig = vault.buildTokenConfig(
            [address(dai), address(usdc)].toMemoryArray().asIERC20()
        );

        // Register should fail, because `enableHookAdjustedAmounts` flag requires unbalanced liquidity to be disabled.
        vm.expectRevert(
            abi.encodeWithSelector(
                IVaultErrors.HookRegistrationFailed.selector,
                poolHooksContract(),
                address(anotherPool),
                address(anotherFactory)
            )
        );

        anotherFactory.registerPool(
            address(anotherPool),
            tokenConfig,
            roleAccounts,
            poolHooksContract(),
            liquidityManagement
        );
    }

    // dynamic fee

    function testOnComputeDynamicSwapFeeHook() public {
        HooksConfig memory hooksConfig = vault.getHooksConfig(pool());
        hooksConfig.shouldCallComputeDynamicSwapFee = true;
        vault.manualSetHooksConfig(pool(), hooksConfig);

        vm.prank(bob);
        vm.expectCall(
            address(poolHooksContract()),
            abi.encodeCall(
                IHooks.onComputeDynamicSwapFeePercentage,
                (
                    PoolSwapParams({
                        kind: SwapKind.EXACT_IN,
                        amountGivenScaled18: DEFAULT_AMOUNT,
                        balancesScaled18: [DEFAULT_AMOUNT, DEFAULT_AMOUNT].toMemoryArray(),
                        indexIn: usdcIdx,
                        indexOut: daiIdx,
                        router: address(router),
                        userData: bytes("")
                    }),
                    pool(),
                    0
                )
            )
        );
        router.swapSingleTokenExactIn(pool(), usdc, dai, DEFAULT_AMOUNT, 0, MAX_UINT256, false, bytes(""));
    }

    function testOnComputeDynamicSwapFeeHookReturningStaticFee() public {
        uint256 staticSwapFeePercentage = 10e16;

        HooksConfig memory hooksConfig = vault.getHooksConfig(pool());
        hooksConfig.shouldCallComputeDynamicSwapFee = true;
        vault.manualSetHooksConfig(pool(), hooksConfig);

        authorizer.grantRole(vault.getActionId(IVaultAdmin.setStaticSwapFeePercentage.selector), alice);
        vm.prank(alice);
        vault.setStaticSwapFeePercentage(pool(), staticSwapFeePercentage);

        vm.prank(bob);
        vm.expectCall(
            address(poolHooksContract()),
            abi.encodeCall(
                IHooks.onComputeDynamicSwapFeePercentage,
                (
                    PoolSwapParams({
                        kind: SwapKind.EXACT_IN,
                        amountGivenScaled18: DEFAULT_AMOUNT,
                        balancesScaled18: [DEFAULT_AMOUNT, DEFAULT_AMOUNT].toMemoryArray(),
                        indexIn: usdcIdx,
                        indexOut: daiIdx,
                        router: address(router),
                        userData: bytes("")
                    }),
                    pool(),
                    staticSwapFeePercentage
                )
            )
        );
        router.swapSingleTokenExactIn(pool(), usdc, dai, DEFAULT_AMOUNT, 0, MAX_UINT256, false, bytes(""));
    }

    function testOnComputeDynamicSwapFeeHookRevert() public {
        HooksConfig memory hooksConfig = vault.getHooksConfig(pool());
        hooksConfig.shouldCallComputeDynamicSwapFee = true;
        vault.manualSetHooksConfig(pool(), hooksConfig);

        // should fail
        PoolHooksMock(poolHooksContract()).setFailOnComputeDynamicSwapFeeHook(true);
        vm.prank(bob);
        vm.expectRevert(IVaultErrors.DynamicSwapFeeHookFailed.selector);
        router.swapSingleTokenExactIn(pool(), usdc, dai, DEFAULT_AMOUNT, DEFAULT_AMOUNT, MAX_UINT256, false, bytes(""));
    }

    // before swap

    function testOnBeforeSwapHook() public {
        HooksConfig memory hooksConfig = vault.getHooksConfig(pool());
        hooksConfig.shouldCallBeforeSwap = true;
        vault.manualSetHooksConfig(pool(), hooksConfig);

        vm.prank(bob);
        vm.expectCall(
            address(poolHooksContract()),
            abi.encodeCall(
                IHooks.onBeforeSwap,
                (
                    PoolSwapParams({
                        kind: SwapKind.EXACT_IN,
                        amountGivenScaled18: DEFAULT_AMOUNT,
                        balancesScaled18: [DEFAULT_AMOUNT, DEFAULT_AMOUNT].toMemoryArray(),
                        indexIn: usdcIdx,
                        indexOut: daiIdx,
                        router: address(router),
                        userData: bytes("")
                    }),
                    pool()
                )
            )
        );
        router.swapSingleTokenExactIn(pool(), usdc, dai, DEFAULT_AMOUNT, 0, MAX_UINT256, false, bytes(""));
    }

    function testOnBeforeSwapHookRevert() public {
        HooksConfig memory hooksConfig = vault.getHooksConfig(pool());
        hooksConfig.shouldCallBeforeSwap = true;
        vault.manualSetHooksConfig(pool(), hooksConfig);

        // should fail
        PoolHooksMock(poolHooksContract()).setFailOnBeforeSwapHook(true);
        vm.prank(bob);
        vm.expectRevert(IVaultErrors.BeforeSwapHookFailed.selector);
        router.swapSingleTokenExactIn(pool(), usdc, dai, DEFAULT_AMOUNT, DEFAULT_AMOUNT, MAX_UINT256, false, bytes(""));
    }

    // after swap

    function testOnAfterSwapHook() public {
        HooksConfig memory hooksConfig = vault.getHooksConfig(pool());
        hooksConfig.shouldCallAfterSwap = true;
        vault.manualSetHooksConfig(pool(), hooksConfig);

        setSwapFeePercentage(DEFAULT_SWAP_FEE_PERCENTAGE);
        vault.manualSetAggregateSwapFeePercentage(pool(), DEFAULT_PROTOCOL_SWAP_FEE_PERCENTAGE);
        PoolHooksMock(poolHooksContract()).setDynamicSwapFeePercentage(DEFAULT_SWAP_FEE_PERCENTAGE);

        uint256 expectedAmountOut = DEFAULT_AMOUNT.mulDown(DEFAULT_SWAP_FEE_PERCENTAGE.complement());
        uint256 swapFee = DEFAULT_AMOUNT.mulDown(DEFAULT_SWAP_FEE_PERCENTAGE);
        uint256 protocolFee = swapFee.mulDown(DEFAULT_PROTOCOL_SWAP_FEE_PERCENTAGE);

        vm.prank(bob);
        vm.expectCall(
            address(poolHooksContract()),
            abi.encodeCall(
                IHooks.onAfterSwap,
                AfterSwapParams({
                    kind: SwapKind.EXACT_IN,
                    tokenIn: usdc,
                    tokenOut: dai,
                    amountInScaled18: DEFAULT_AMOUNT,
                    amountOutScaled18: expectedAmountOut,
                    tokenInBalanceScaled18: DEFAULT_AMOUNT * 2 - protocolFee,
                    tokenOutBalanceScaled18: DEFAULT_AMOUNT - expectedAmountOut,
                    amountCalculatedScaled18: expectedAmountOut,
                    amountCalculatedRaw: expectedAmountOut,
                    router: address(router),
                    pool: pool(),
                    userData: bytes("")
                })
            )
        );

        router.swapSingleTokenExactIn(pool(), usdc, dai, DEFAULT_AMOUNT, 0, MAX_UINT256, false, bytes(""));
    }

    function testOnAfterSwapHookRevert() public {
        HooksConfig memory hooksConfig = vault.getHooksConfig(pool());
        hooksConfig.shouldCallAfterSwap = true;
        vault.manualSetHooksConfig(pool(), hooksConfig);

        // Should fail.
        PoolHooksMock(poolHooksContract()).setFailOnAfterSwapHook(true);
        vm.prank(bob);
        vm.expectRevert(IVaultErrors.AfterSwapHookFailed.selector);
        router.swapSingleTokenExactIn(pool(), usdc, dai, DEFAULT_AMOUNT, DEFAULT_AMOUNT, MAX_UINT256, false, bytes(""));
    }

    // Before add

    function testOnBeforeAddLiquidityFlag() public {
        PoolHooksMock(poolHooksContract()).setFailOnBeforeAddLiquidityHook(true);

        vm.prank(bob);
        // Doesn't fail, does not call hooks.
        router.addLiquidityUnbalanced(
            pool(),
            [DEFAULT_AMOUNT, DEFAULT_AMOUNT].toMemoryArray(),
            DEFAULT_BPT_AMOUNT_ROUND_DOWN,
            false,
            bytes("")
        );
    }

    function testOnBeforeAddLiquidityHook() public {
        HooksConfig memory hooksConfig = vault.getHooksConfig(pool());
        hooksConfig.shouldCallBeforeAddLiquidity = true;
        vault.manualSetHooksConfig(pool(), hooksConfig);

        vm.prank(bob);
        vm.expectCall(
            address(poolHooksContract()),
            abi.encodeCall(
                IHooks.onBeforeAddLiquidity,
                (
                    address(router),
                    pool(),
                    AddLiquidityKind.UNBALANCED,
                    [DEFAULT_AMOUNT, DEFAULT_AMOUNT].toMemoryArray(),
                    DEFAULT_BPT_AMOUNT_ROUND_DOWN,
                    [DEFAULT_AMOUNT, DEFAULT_AMOUNT].toMemoryArray(),
                    bytes("")
                )
            )
        );
        router.addLiquidityUnbalanced(
            pool(),
            [DEFAULT_AMOUNT, DEFAULT_AMOUNT].toMemoryArray(),
            DEFAULT_BPT_AMOUNT_ROUND_DOWN,
            false,
            bytes("")
        );
    }

    function testOnBeforeAddLiquidityHookRevert() public {
        HooksConfig memory hooksConfig = vault.getHooksConfig(pool());
        hooksConfig.shouldCallBeforeAddLiquidity = true;
        vault.manualSetHooksConfig(pool(), hooksConfig);

        // Force failure on AfterRemoveLiquidityHook.
        PoolHooksMock(poolHooksContract()).setFailOnBeforeAddLiquidityHook(true);

        vm.prank(bob);
        vm.expectRevert(IVaultErrors.BeforeAddLiquidityHookFailed.selector);
        router.addLiquidityUnbalanced(
            pool(),
            [DEFAULT_AMOUNT, DEFAULT_AMOUNT].toMemoryArray(),
            DEFAULT_BPT_AMOUNT_ROUND_DOWN,
            false,
            bytes("")
        );
    }

    // Before remove

    function testOnBeforeRemoveLiquidityFlag() public {
        PoolHooksMock(poolHooksContract()).setFailOnBeforeRemoveLiquidityHook(true);

        vm.prank(alice);
        router.addLiquidityUnbalanced(
            pool(),
            [DEFAULT_AMOUNT, DEFAULT_AMOUNT].toMemoryArray(),
            DEFAULT_BPT_AMOUNT_ROUND_DOWN,
            false,
            bytes("")
        );

        vm.prank(alice);
        router.removeLiquidityProportional(
            pool(),
            DEFAULT_BPT_AMOUNT_ROUND_DOWN,
            [DEFAULT_AMOUNT_ROUND_DOWN, DEFAULT_AMOUNT_ROUND_DOWN].toMemoryArray(),
            false,
            bytes("")
        );
    }

    function testOnBeforeRemoveLiquidityHook() public {
        HooksConfig memory hooksConfig = vault.getHooksConfig(pool());
        hooksConfig.shouldCallBeforeRemoveLiquidity = true;
        vault.manualSetHooksConfig(pool(), hooksConfig);

        vm.prank(alice);
        router.addLiquidityUnbalanced(
            pool(),
            [DEFAULT_AMOUNT, DEFAULT_AMOUNT].toMemoryArray(),
            DEFAULT_BPT_AMOUNT_ROUND_DOWN,
            false,
            bytes("")
        );

        vm.expectCall(
            address(poolHooksContract()),
            abi.encodeCall(
                IHooks.onBeforeRemoveLiquidity,
                (
                    address(router),
                    pool(),
                    RemoveLiquidityKind.PROPORTIONAL,
                    DEFAULT_BPT_AMOUNT_ROUND_DOWN,
                    [DEFAULT_AMOUNT_ROUND_DOWN, DEFAULT_AMOUNT_ROUND_DOWN].toMemoryArray(),
                    [2 * DEFAULT_AMOUNT, 2 * DEFAULT_AMOUNT].toMemoryArray(),
                    bytes("")
                )
            )
        );
        vm.prank(alice);
        router.removeLiquidityProportional(
            pool(),
            DEFAULT_BPT_AMOUNT_ROUND_DOWN,
            [DEFAULT_AMOUNT_ROUND_DOWN, DEFAULT_AMOUNT_ROUND_DOWN].toMemoryArray(),
            false,
            bytes("")
        );
    }

    function testOnBeforeRemoveLiquidityHookRevert() public {
        HooksConfig memory hooksConfig = vault.getHooksConfig(pool());
        hooksConfig.shouldCallBeforeRemoveLiquidity = true;
        vault.manualSetHooksConfig(pool(), hooksConfig);

        // Add liquidity first, so Alice can remove it later.
        vm.prank(alice);
        router.addLiquidityUnbalanced(
            pool(),
            [DEFAULT_AMOUNT, DEFAULT_AMOUNT].toMemoryArray(),
            DEFAULT_BPT_AMOUNT_ROUND_DOWN,
            false,
            bytes("")
        );

        // Force failure on AfterRemoveLiquidityHook.
        PoolHooksMock(poolHooksContract()).setFailOnBeforeRemoveLiquidityHook(true);

        vm.prank(alice);
        vm.expectRevert(IVaultErrors.BeforeRemoveLiquidityHookFailed.selector);
        router.removeLiquidityProportional(
            pool(),
            DEFAULT_BPT_AMOUNT_ROUND_DOWN,
            [DEFAULT_AMOUNT_ROUND_DOWN, DEFAULT_AMOUNT_ROUND_DOWN].toMemoryArray(),
            false,
            bytes("")
        );
    }

    // After add

    function testOnAfterAddLiquidityFlag() public {
        PoolHooksMock(poolHooksContract()).setFailOnAfterAddLiquidityHook(true);

        vm.prank(bob);
        // Doesn't fail, does not call hooks.
        router.addLiquidityUnbalanced(
            pool(),
            [DEFAULT_AMOUNT, DEFAULT_AMOUNT].toMemoryArray(),
            DEFAULT_BPT_AMOUNT_ROUND_DOWN,
            false,
            bytes("")
        );
    }

    function testOnAfterAddLiquidityHook() public {
        HooksConfig memory hooksConfig = vault.getHooksConfig(pool());
        hooksConfig.shouldCallAfterAddLiquidity = true;
        vault.manualSetHooksConfig(pool(), hooksConfig);

        vm.prank(bob);
        vm.expectCall(
            address(poolHooksContract()),
            abi.encodeCall(
                IHooks.onAfterAddLiquidity,
                (
                    address(router),
                    pool(),
                    AddLiquidityKind.UNBALANCED,
                    [DEFAULT_AMOUNT, DEFAULT_AMOUNT].toMemoryArray(),
                    [DEFAULT_AMOUNT, DEFAULT_AMOUNT].toMemoryArray(),
                    DEFAULT_BPT_AMOUNT_ROUND_DOWN,
                    [2 * DEFAULT_AMOUNT, 2 * DEFAULT_AMOUNT].toMemoryArray(),
                    bytes("")
                )
            )
        );
        router.addLiquidityUnbalanced(
            pool(),
            [DEFAULT_AMOUNT, DEFAULT_AMOUNT].toMemoryArray(),
            DEFAULT_BPT_AMOUNT_ROUND_DOWN,
            false,
            bytes("")
        );
    }

    function testOnAfterAddLiquidityHookRevert() public {
        HooksConfig memory hooksConfig = vault.getHooksConfig(pool());
        hooksConfig.shouldCallAfterAddLiquidity = true;
        vault.manualSetHooksConfig(pool(), hooksConfig);

        // Force failure on AfterRemoveLiquidityHook.
        PoolHooksMock(poolHooksContract()).setFailOnAfterAddLiquidityHook(true);

        vm.prank(bob);
        vm.expectRevert(IVaultErrors.AfterAddLiquidityHookFailed.selector);
        router.addLiquidityUnbalanced(
            pool(),
            [DEFAULT_AMOUNT, DEFAULT_AMOUNT].toMemoryArray(),
            DEFAULT_BPT_AMOUNT_ROUND_DOWN,
            false,
            bytes("")
        );
    }

    function testOnAfterAddLiquidityHookEmptyHookAdjustedAmounts() public {
        HooksConfig memory hooksConfig = vault.getHooksConfig(pool());
        hooksConfig.shouldCallAfterAddLiquidity = true;
        vault.manualSetHooksConfig(pool(), hooksConfig);

        // Return empty hook adjusted amounts.
        PoolHooksMock(poolHooksContract()).enableForcedHookAdjustedAmountsLiquidity(new uint256[](0));

        vm.prank(bob);
        vm.expectRevert(IVaultErrors.AfterAddLiquidityHookFailed.selector);
        router.addLiquidityUnbalanced(
            pool(),
            [DEFAULT_AMOUNT, DEFAULT_AMOUNT].toMemoryArray(),
            DEFAULT_BPT_AMOUNT_ROUND_DOWN,
            false,
            bytes("")
        );
    }

    // After remove

    function testOnAfterRemoveLiquidityFlag() public {
        PoolHooksMock(poolHooksContract()).setFailOnAfterRemoveLiquidityHook(true);

        vm.prank(alice);
        router.addLiquidityUnbalanced(
            pool(),
            [DEFAULT_AMOUNT, DEFAULT_AMOUNT].toMemoryArray(),
            DEFAULT_BPT_AMOUNT_ROUND_DOWN,
            false,
            bytes("")
        );

        vm.prank(alice);
        router.removeLiquidityProportional(
            pool(),
            DEFAULT_BPT_AMOUNT_ROUND_DOWN,
            [DEFAULT_AMOUNT_ROUND_DOWN, DEFAULT_AMOUNT_ROUND_DOWN].toMemoryArray(),
            false,
            bytes("")
        );
    }

    function testOnAfterRemoveLiquidityHook() public {
        HooksConfig memory hooksConfig = vault.getHooksConfig(pool());
        hooksConfig.shouldCallAfterRemoveLiquidity = true;
        vault.manualSetHooksConfig(pool(), hooksConfig);

        vm.prank(alice);
        router.addLiquidityUnbalanced(
            pool(),
            [DEFAULT_AMOUNT, DEFAULT_AMOUNT].toMemoryArray(),
            DEFAULT_BPT_AMOUNT_ROUND_DOWN,
            false,
            bytes("")
        );

        vm.expectCall(
            address(poolHooksContract()),
            abi.encodeCall(
                IHooks.onAfterRemoveLiquidity,
                (
                    address(router),
                    pool(),
                    RemoveLiquidityKind.PROPORTIONAL,
                    DEFAULT_BPT_AMOUNT_ROUND_DOWN,
                    [DEFAULT_AMOUNT - 1, DEFAULT_AMOUNT - 1].toMemoryArray(),
                    [DEFAULT_AMOUNT - 1, DEFAULT_AMOUNT - 1].toMemoryArray(),
                    [DEFAULT_AMOUNT + 1, DEFAULT_AMOUNT + 1].toMemoryArray(),
                    bytes("")
                )
            )
        );

        vm.prank(alice);
        router.removeLiquidityProportional(
            pool(),
            DEFAULT_BPT_AMOUNT_ROUND_DOWN,
            [DEFAULT_AMOUNT_ROUND_DOWN, DEFAULT_AMOUNT_ROUND_DOWN].toMemoryArray(),
            false,
            bytes("")
        );
    }

    function testOnAfterRemoveLiquidityHookRevert() public {
        HooksConfig memory hooksConfig = vault.getHooksConfig(pool());
        hooksConfig.shouldCallAfterRemoveLiquidity = true;
        vault.manualSetHooksConfig(pool(), hooksConfig);

        // Add liquidity first, so Alice can remove it later.
        vm.prank(alice);
        router.addLiquidityUnbalanced(
            pool(),
            [DEFAULT_AMOUNT, DEFAULT_AMOUNT].toMemoryArray(),
            DEFAULT_BPT_AMOUNT_ROUND_DOWN,
            false,
            bytes("")
        );

        // Force failure on AfterRemoveLiquidityHook.
        PoolHooksMock(poolHooksContract()).setFailOnAfterRemoveLiquidityHook(true);

        vm.prank(alice);
        vm.expectRevert(IVaultErrors.AfterRemoveLiquidityHookFailed.selector);
        router.removeLiquidityProportional(
            pool(),
            DEFAULT_BPT_AMOUNT_ROUND_DOWN,
            [DEFAULT_AMOUNT_ROUND_DOWN, DEFAULT_AMOUNT_ROUND_DOWN].toMemoryArray(),
            false,
            bytes("")
        );
    }

    function testOnAfterRemoveLiquidityHookEmptyHookAdjustedAmounts() public {
        HooksConfig memory hooksConfig = vault.getHooksConfig(pool());
        hooksConfig.shouldCallAfterRemoveLiquidity = true;
        vault.manualSetHooksConfig(pool(), hooksConfig);

        // Add liquidity first, so Alice can remove it later.
        vm.prank(alice);
        router.addLiquidityUnbalanced(
            pool(),
            [DEFAULT_AMOUNT, DEFAULT_AMOUNT].toMemoryArray(),
            DEFAULT_BPT_AMOUNT_ROUND_DOWN,
            false,
            bytes("")
        );

        // Return empty hook adjusted amounts.
        PoolHooksMock(poolHooksContract()).enableForcedHookAdjustedAmountsLiquidity(new uint256[](0));

        vm.prank(alice);
        vm.expectRevert(IVaultErrors.AfterRemoveLiquidityHookFailed.selector);
        router.removeLiquidityProportional(
            pool(),
            DEFAULT_BPT_AMOUNT_ROUND_DOWN,
            [DEFAULT_AMOUNT_ROUND_DOWN, DEFAULT_AMOUNT_ROUND_DOWN].toMemoryArray(),
            false,
            bytes("")
        );
    }
}
