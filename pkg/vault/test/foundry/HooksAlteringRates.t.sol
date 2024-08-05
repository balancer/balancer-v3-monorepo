// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IPoolLiquidity } from "@balancer-labs/v3-interfaces/contracts/vault/IPoolLiquidity.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";

import { PoolMock } from "../../contracts/test/PoolMock.sol";
import { PoolHooksMock } from "../../contracts/test/PoolHooksMock.sol";
import { RateProviderMock } from "../../contracts/test/RateProviderMock.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract HooksAlteringRatesTest is BaseVaultTest {
    using CastingHelpers for address[];
    using ArrayHelpers for *;

    uint256 internal daiIdx;
    uint256 internal usdcIdx;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        HooksConfig memory config = vault.getHooksConfig(pool);
        config.shouldCallBeforeSwap = true;
        vault.manualSetHooksConfig(pool, config);

        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));
    }

    function createPool() internal virtual override returns (address) {
        IRateProvider[] memory rateProviders = new IRateProvider[](2);
        // Rate providers will by sorted along with tokens by `buildTokenConfig`.
        rateProvider = new RateProviderMock();
        rateProviders[0] = rateProvider;

        TokenConfig[] memory tokenConfig = vault.buildTokenConfig(
            [address(dai), address(usdc)].toMemoryArray().asIERC20(),
            rateProviders
        );

        PoolMock newPool = new PoolMock(IVault(address(vault)), "ERC20 Pool", "ERC20POOL");
        vm.label(address(newPool), "pool");

        factoryMock.registerTestPool(address(newPool), tokenConfig, poolHooksContract, lp);

        return address(newPool);
    }

    function testOnBeforeSwapHookAltersRate() public {
        // Change rate of first token.
        PoolHooksMock(poolHooksContract).setChangeTokenRateOnBeforeSwapHook(true, rateProvider, 0.5e18);

        uint256 rateAdjustedAmount = defaultAmount / 2;

        uint256[] memory expectedBalances = new uint256[](2);
        expectedBalances[daiIdx] = rateAdjustedAmount;
        expectedBalances[usdcIdx] = defaultAmount;

        // Check that the swap gets balances and amount given that reflect the updated rate.
        vm.prank(bob);
        vm.expectCall(
            pool,
            abi.encodeWithSelector(
                IBasePool.onSwap.selector,
                PoolSwapParams({
                    kind: SwapKind.EXACT_IN,
                    amountGivenScaled18: rateAdjustedAmount,
                    balancesScaled18: expectedBalances,
                    indexIn: daiIdx,
                    indexOut: usdcIdx,
                    router: address(router),
                    userData: bytes("")
                })
            )
        );

        router.swapSingleTokenExactIn(pool, dai, usdc, defaultAmount, 0, MAX_UINT256, false, bytes(""));
    }

    function testOnBeforeInitializeHookAltersRate() public {
        IRateProvider[] memory rateProviders = new IRateProvider[](2);
        rateProviders[0] = rateProvider;

        TokenConfig[] memory tokenConfig = vault.buildTokenConfig(
            [address(dai), address(usdc)].toMemoryArray().asIERC20(),
            rateProviders
        );

        PoolMock newPool = new PoolMock(IVault(address(vault)), "ERC20 Pool", "ERC20POOL");
        vm.label(address(newPool), "new-pool");

        factoryMock.registerTestPool(address(newPool), tokenConfig, poolHooksContract, lp);

        HooksConfig memory config = vault.getHooksConfig(address(newPool));
        config.shouldCallBeforeInitialize = true;
        config.shouldCallAfterInitialize = true;
        vault.manualSetHooksConfig(address(newPool), config);

        // Change rate of first token.
        PoolHooksMock(poolHooksContract).setChangeTokenRateOnBeforeInitializeHook(true, rateProvider, 0.5e18);

        uint256 rateAdjustedAmount = defaultAmount / 2;

        uint256 bptAmount = rateAdjustedAmount + defaultAmount - _MINIMUM_BPT;

        uint256[] memory expectedAmounts = new uint256[](2);
        expectedAmounts[daiIdx] = rateAdjustedAmount;
        expectedAmounts[usdcIdx] = defaultAmount;

        // Cannot intercept _initialize, but can check the same values in the AfterInitialize hook.
        vm.prank(bob);
        vm.expectCall(
            address(poolHooksContract),
            abi.encodeWithSelector(IHooks.onAfterInitialize.selector, expectedAmounts, bptAmount, "")
        );

        router.initialize(
            address(newPool),
            InputHelpers.sortTokens([address(dai), address(usdc)].toMemoryArray().asIERC20()),
            [defaultAmount, defaultAmount].toMemoryArray(),
            0,
            false,
            ""
        );
    }

    function testOnBeforeAddLiquidityHookAltersRate() public {
        HooksConfig memory config = vault.getHooksConfig(pool);
        config.shouldCallBeforeAddLiquidity = true;
        config.shouldCallAfterAddLiquidity = true;
        vault.manualSetHooksConfig(pool, config);

        // Change rate of first token.
        PoolHooksMock(poolHooksContract).setChangeTokenRateOnBeforeAddLiquidityHook(true, rateProvider, 0.5e18);

        uint256 rateAdjustedAmount = defaultAmount / 2;

        // Unbalanced add sets amounts to maxAmounts. We can't intercept `_addLiquidity`, but can verify
        // maxAmounts are updated by inspecting the amountsIn.

        uint256[] memory expectedAmountsIn = new uint256[](2);
        uint256[] memory expectedBalances = new uint256[](2);

        expectedAmountsIn[daiIdx] = rateAdjustedAmount;
        expectedAmountsIn[usdcIdx] = defaultAmount;

        expectedBalances[daiIdx] = defaultAmount;
        expectedBalances[usdcIdx] = defaultAmount * 2;

        vm.prank(bob);
        vm.expectCall(
            address(poolHooksContract),
            abi.encodeWithSelector(
                IHooks.onAfterAddLiquidity.selector,
                router,
                pool,
                AddLiquidityKind.UNBALANCED,
                expectedAmountsIn,
                [defaultAmount, defaultAmount].toMemoryArray(),
                defaultAmount * 2,
                expectedBalances,
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

    function testOnBeforeRemoveLiquidityHookAlterRate() public {
        HooksConfig memory config = vault.getHooksConfig(pool);
        config.shouldCallBeforeRemoveLiquidity = true;
        vault.manualSetHooksConfig(pool, config);

        // Change rate of first token.
        PoolHooksMock(poolHooksContract).setChangeTokenRateOnBeforeRemoveLiquidityHook(true, rateProvider, 0.5e18);

        uint256 rateAdjustedAmount = defaultAmount / 2;

        vm.prank(alice);
        router.addLiquidityUnbalanced(
            pool,
            [defaultAmount, defaultAmount].toMemoryArray(),
            bptAmount,
            false,
            bytes("")
        );

        uint256[] memory expectedAmountsOut = new uint256[](2);
        uint256[] memory expectedBalances = new uint256[](2);

        expectedAmountsOut[daiIdx] = rateAdjustedAmount;
        expectedAmountsOut[usdcIdx] = defaultAmountRoundDown;

        expectedBalances[daiIdx] = defaultAmount;
        expectedBalances[usdcIdx] = defaultAmount * 2;

        // removeLiquidityCustom passes the minAmountsOut to the callback, so we can check that they are updated.
        vm.expectCall(
            pool,
            abi.encodeWithSelector(
                IPoolLiquidity.onRemoveLiquidityCustom.selector,
                router,
                bptAmount,
                expectedAmountsOut,
                expectedBalances,
                bytes("")
            )
        );
        vm.prank(alice);
        router.removeLiquidityCustom(
            pool,
            bptAmount,
            [defaultAmountRoundDown, defaultAmountRoundDown].toMemoryArray(),
            false,
            bytes("")
        );
    }
}
