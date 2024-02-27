// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IPoolHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IPoolHooks.sol";
import { IPoolLiquidity } from "@balancer-labs/v3-interfaces/contracts/vault/IPoolLiquidity.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";

import { PoolMock } from "../../contracts/test/PoolMock.sol";
import { RateProviderMock } from "../../contracts/test/RateProviderMock.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract HooksAlteringRatesTest is BaseVaultTest {
    using ArrayHelpers for *;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        PoolConfig memory config = vault.getPoolConfig(address(pool));
        config.hooks.shouldCallBeforeSwap = true;
        vault.setConfig(address(pool), config);
    }

    function createPool() internal virtual override returns (address) {
        IRateProvider[] memory rateProviders = new IRateProvider[](2);
        rateProviders[0] = new RateProviderMock();

        PoolMock newPool = new PoolMock(
            IVault(address(vault)),
            "ERC20 Pool",
            "ERC20POOL",
            vault.buildTokenConfig([address(dai), address(usdc)].toMemoryArray().asIERC20(), rateProviders),
            true,
            365 days,
            address(0)
        );
        vm.label(address(newPool), "pool");
        return address(newPool);
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
        router.swapSingleTokenExactIn(address(pool), usdc, dai, defaultAmount, 0, type(uint256).max, false, bytes(""));
    }

    function testOnBeforeSwapHookAltersRate() public {
        // Change rate of first token
        PoolMock(pool).setChangeTokenRateOnBeforeSwapHook(true, 0.5e18);

        uint256 rateAdjustedAmount = defaultAmount / 2;

        // Check that the swap gets balances and amount given that reflect the updated rate
        vm.prank(bob);
        vm.expectCall(
            address(pool),
            abi.encodeWithSelector(
                IBasePool.onSwap.selector,
                IBasePool.SwapParams({
                    kind: SwapKind.EXACT_IN,
                    amountGivenScaled18: rateAdjustedAmount,
                    balancesScaled18: [rateAdjustedAmount, defaultAmount].toMemoryArray(),
                    indexIn: 0,
                    indexOut: 1,
                    sender: address(router),
                    userData: bytes("")
                })
            )
        );

        router.swapSingleTokenExactIn(address(pool), dai, usdc, defaultAmount, 0, type(uint256).max, false, bytes(""));
    }

    function testOnBeforeInitializeHook() public {
        PoolMock newPool = new PoolMock(
            IVault(address(vault)),
            "ERC20 Pool",
            "ERC20POOL",
            vault.buildTokenConfig([address(dai), address(usdc)].toMemoryArray().asIERC20()),
            true,
            365 days,
            address(0)
        );
        vm.label(address(newPool), "new-pool");

        PoolConfig memory config = vault.getPoolConfig(address(newPool));
        config.hooks.shouldCallBeforeInitialize = true;
        vault.setConfig(address(newPool), config);

        vm.prank(bob);
        vm.expectCall(
            address(newPool),
            abi.encodeWithSelector(
                IPoolHooks.onBeforeInitialize.selector,
                [defaultAmount, defaultAmount].toMemoryArray(),
                ""
            )
        );
        router.initialize(
            address(newPool),
            [address(dai), address(usdc)].toMemoryArray().asIERC20(),
            [defaultAmount, defaultAmount].toMemoryArray(),
            0,
            false,
            ""
        );
    }

    function testOnBeforeInitializeHookAltersRate() public {
        IRateProvider[] memory rateProviders = new IRateProvider[](2);
        rateProviders[0] = new RateProviderMock();

        PoolMock newPool = new PoolMock(
            IVault(address(vault)),
            "ERC20 Pool",
            "ERC20POOL",
            vault.buildTokenConfig([address(dai), address(usdc)].toMemoryArray().asIERC20(), rateProviders),
            true,
            365 days,
            address(0)
        );
        vm.label(address(newPool), "new-pool");

        PoolConfig memory config = vault.getPoolConfig(address(newPool));
        config.hooks.shouldCallBeforeInitialize = true;
        config.hooks.shouldCallAfterInitialize = true;
        vault.setConfig(address(newPool), config);

        // Change rate of first token
        PoolMock(newPool).setChangeTokenRateOnBeforeInitializeHook(true, 0.5e18);

        uint256 rateAdjustedAmount = defaultAmount / 2;

        uint256 bptAmount = rateAdjustedAmount + defaultAmount - _MINIMUM_BPT;

        // Cannot intercept _initialize, but can check the same values in the AfterInitialize hook
        vm.prank(bob);
        vm.expectCall(
            address(newPool),
            abi.encodeWithSelector(
                IPoolHooks.onAfterInitialize.selector,
                [rateAdjustedAmount, defaultAmount].toMemoryArray(),
                bptAmount,
                ""
            )
        );

        router.initialize(
            address(newPool),
            [address(dai), address(usdc)].toMemoryArray().asIERC20(),
            [defaultAmount, defaultAmount].toMemoryArray(),
            0,
            false,
            ""
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

    function testOnBeforeAddLiquidityHookAltersRate() public {
        PoolConfig memory config = vault.getPoolConfig(address(pool));
        config.hooks.shouldCallBeforeAddLiquidity = true;
        config.hooks.shouldCallAfterAddLiquidity = true;
        vault.setConfig(address(pool), config);

        // Change rate of first token
        PoolMock(pool).setChangeTokenRateOnBeforeAddLiquidityHook(true, 0.5e18);

        uint256 rateAdjustedAmount = defaultAmount / 2;

        // Unbalanced add sets amounts to maxAmounts. We can't intercept `_addLliquidity`, but can verify
        // maxAmounts are updated by inspecting the amountsIn.

        vm.prank(bob);
        vm.expectCall(
            address(pool),
            abi.encodeWithSelector(
                IPoolHooks.onAfterAddLiquidity.selector,
                bob,
                [rateAdjustedAmount, defaultAmount].toMemoryArray(),
                defaultAmount * 2,
                [defaultAmount, defaultAmount * 2].toMemoryArray(),
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

    function testOnBeforeRemoveLiquidityHookAlterRate() public {
        PoolConfig memory config = vault.getPoolConfig(address(pool));
        config.hooks.shouldCallBeforeRemoveLiquidity = true;
        vault.setConfig(address(pool), config);

        // Change rate of first token
        PoolMock(pool).setChangeTokenRateOnBeforeRemoveLiquidityHook(true, 0.5e18);

        uint256 rateAdjustedAmount = defaultAmount / 2;

        vm.prank(alice);
        router.addLiquidityUnbalanced(
            address(pool),
            [defaultAmount, defaultAmount].toMemoryArray(),
            bptAmount,
            false,
            bytes("")
        );

        // removeLiquidityCustom passes the minAmountsOut to the callback, so we can check that they are updated.
        vm.expectCall(
            address(pool),
            abi.encodeWithSelector(
                IPoolLiquidity.onRemoveLiquidityCustom.selector,
                alice,
                bptAmount,
                [rateAdjustedAmount, defaultAmountRoundDown].toMemoryArray(),
                [defaultAmount, 2 * defaultAmount].toMemoryArray(),
                bytes("")
            )
        );
        vm.prank(alice);
        router.removeLiquidityCustom(
            address(pool),
            bptAmount,
            [defaultAmountRoundDown, defaultAmountRoundDown].toMemoryArray(),
            false,
            bytes("")
        );
    }
}
