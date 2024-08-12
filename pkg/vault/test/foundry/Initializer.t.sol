// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { HooksConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";

import { PoolHooksMock } from "../../contracts/test/PoolHooksMock.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract InitializerTest is BaseVaultTest {
    using CastingHelpers for address[];
    using ArrayHelpers for *;

    IERC20[] standardPoolTokens;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        HooksConfig memory config = vault.getHooksConfig(pool);
        config.shouldCallBeforeInitialize = true;
        config.shouldCallAfterInitialize = true;
        vault.manualSetHooksConfig(pool, config);

        standardPoolTokens = InputHelpers.sortTokens([address(dai), address(usdc)].toMemoryArray().asIERC20());
    }

    function initPool() internal override {}

    function testNoRevertWithZeroConfig() public {
        HooksConfig memory config = vault.getHooksConfig(pool);
        config.shouldCallBeforeInitialize = false;
        config.shouldCallAfterInitialize = false;
        vault.manualSetHooksConfig(pool, config);

        PoolHooksMock(poolHooksContract).setFailOnBeforeInitializeHook(true);
        PoolHooksMock(poolHooksContract).setFailOnAfterInitializeHook(true);

        vm.prank(bob);
        router.initialize(
            pool,
            standardPoolTokens,
            [defaultAmount, defaultAmount].toMemoryArray(),
            0,
            false,
            bytes("0xff")
        );
    }

    function testOnBeforeInitializeHook() public {
        vm.prank(bob);
        vm.expectCall(
            address(poolHooksContract),
            abi.encodeWithSelector(
                IHooks.onBeforeInitialize.selector,
                [defaultAmount, defaultAmount].toMemoryArray(),
                bytes("0xff")
            )
        );
        router.initialize(
            pool,
            standardPoolTokens,
            [defaultAmount, defaultAmount].toMemoryArray(),
            0,
            false,
            bytes("0xff")
        );
    }

    function testOnBeforeInitializeHookRevert() public {
        PoolHooksMock(poolHooksContract).setFailOnBeforeInitializeHook(true);
        vm.prank(bob);
        vm.expectRevert(IVaultErrors.BeforeInitializeHookFailed.selector);
        router.initialize(
            pool,
            standardPoolTokens,
            [defaultAmount, defaultAmount].toMemoryArray(),
            0,
            false,
            bytes("0xff")
        );
    }

    function testOnAfterInitializeHook() public {
        vm.prank(bob);
        vm.expectCall(
            address(poolHooksContract),
            abi.encodeWithSelector(
                IHooks.onAfterInitialize.selector,
                [defaultAmount, defaultAmount].toMemoryArray(),
                2 * defaultAmount - MIN_BPT,
                bytes("0xff")
            )
        );
        router.initialize(
            pool,
            standardPoolTokens,
            [defaultAmount, defaultAmount].toMemoryArray(),
            0,
            false,
            bytes("0xff")
        );
    }

    function testOnAfterInitializeHookRevert() public {
        PoolHooksMock(poolHooksContract).setFailOnAfterInitializeHook(true);
        vm.prank(bob);
        vm.expectRevert(IVaultErrors.AfterInitializeHookFailed.selector);
        router.initialize(
            pool,
            standardPoolTokens,
            [defaultAmount, defaultAmount].toMemoryArray(),
            0,
            false,
            bytes("0xff")
        );
    }

    function testInitializeWithDust() public {
        dai.mint(address(vault), 1);
        usdc.mint(address(vault), 1);

        vm.prank(bob);
        router.initialize(
            pool,
            standardPoolTokens,
            [defaultAmount, defaultAmount].toMemoryArray(),
            0,
            false,
            bytes("0xff")
        );
    }
}
