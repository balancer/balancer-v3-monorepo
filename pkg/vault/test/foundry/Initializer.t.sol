// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { IPoolCallbacks } from "@balancer-labs/v3-interfaces/contracts/vault/IPoolCallbacks.sol";
import { IRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IRouter.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { CallbackFailed } from "@balancer-labs/v3-interfaces/contracts/vault/VaultErrors.sol";
import { PoolConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { ERC20TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC20TestToken.sol";
import { BasicAuthorizerMock } from "@balancer-labs/v3-solidity-utils/contracts/test/BasicAuthorizerMock.sol";
import { WETHTestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/WETHTestToken.sol";

import { PoolMock } from "../../contracts/test/PoolMock.sol";
import { Router } from "../../contracts/Router.sol";
import { VaultMock } from "../../contracts/test/VaultMock.sol";
import { VaultExtensionMock } from "../../contracts/test/VaultExtensionMock.sol";

import { VaultMockDeployer } from "./utils/VaultMockDeployer.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract InitializerTest is BaseVaultTest {
    using ArrayHelpers for *;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        PoolConfig memory config = vault.getPoolConfig(address(pool));
        config.callbacks.shouldCallBeforeInitialize = true;
        config.callbacks.shouldCallAfterInitialize = true;
        vault.setConfig(address(pool), config);
    }

    function initPool() internal override {}

    function testNoRevertWithZeroConfig() public {
        PoolConfig memory config = vault.getPoolConfig(address(pool));
        config.callbacks.shouldCallBeforeInitialize = false;
        config.callbacks.shouldCallAfterInitialize = false;
        vault.setConfig(address(pool), config);

        PoolMock(pool).setFailOnBeforeInitializeCallback(true);
        PoolMock(pool).setFailOnAfterInitializeCallback(true);

        vm.prank(bob);
        router.initialize(
            address(pool),
            [address(dai), address(usdc)].toMemoryArray().asIERC20(),
            [defaultAmount, defaultAmount].toMemoryArray(),
            0,
            false,
            bytes("0xff")
        );
    }

    function testOnBeforeInitializeCallback() public {
        vm.prank(bob);
        vm.expectCall(
            address(pool),
            abi.encodeWithSelector(
                IPoolCallbacks.onBeforeInitialize.selector,
                [defaultAmount, defaultAmount].toMemoryArray(),
                bytes("0xff")
            )
        );
        router.initialize(
            address(pool),
            [address(dai), address(usdc)].toMemoryArray().asIERC20(),
            [defaultAmount, defaultAmount].toMemoryArray(),
            0,
            false,
            bytes("0xff")
        );
    }

    function testOnBeforeInitializeCallbackRevert() public {
        PoolMock(pool).setFailOnBeforeInitializeCallback(true);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(CallbackFailed.selector));
        router.initialize(
            address(pool),
            [address(dai), address(usdc)].toMemoryArray().asIERC20(),
            [defaultAmount, defaultAmount].toMemoryArray(),
            0,
            false,
            bytes("0xff")
        );
    }

    function testOnAfterInitializeCallback() public {
        vm.prank(bob);
        vm.expectCall(
            address(pool),
            abi.encodeWithSelector(
                IPoolCallbacks.onAfterInitialize.selector,
                [defaultAmount, defaultAmount].toMemoryArray(),
                2 * defaultAmount,
                bytes("0xff")
            )
        );
        router.initialize(
            address(pool),
            [address(dai), address(usdc)].toMemoryArray().asIERC20(),
            [defaultAmount, defaultAmount].toMemoryArray(),
            0,
            false,
            bytes("0xff")
        );
    }

    function testOnAfterInitializeCallbackRevert() public {
        PoolMock(pool).setFailOnAfterInitializeCallback(true);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(CallbackFailed.selector));
        router.initialize(
            address(pool),
            [address(dai), address(usdc)].toMemoryArray().asIERC20(),
            [defaultAmount, defaultAmount].toMemoryArray(),
            0,
            false,
            bytes("0xff")
        );
    }
}
