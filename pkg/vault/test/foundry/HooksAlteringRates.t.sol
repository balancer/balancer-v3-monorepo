// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IPoolHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IPoolHooks.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IVaultExtension } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultExtension.sol";
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
}
