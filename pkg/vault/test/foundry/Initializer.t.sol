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

contract InitializerTest is Test {
    using ArrayHelpers for *;

    VaultMock vault;
    VaultExtensionMock vaultExtension;
    IRouter router;
    BasicAuthorizerMock authorizer;
    PoolMock pool;
    ERC20TestToken USDC;
    ERC20TestToken DAI;
    address alice = vm.addr(1);
    address bob = vm.addr(2);

    uint256 constant BPT_AMOUNT = 2e3 * 1e18;
    uint256 constant BPT_AMOUNT_ROUND_DOWN = BPT_AMOUNT - 1;
    uint256 constant DEFAULT_AMOUNT = 1e3 * 1e18;
    uint256 constant DEFAULT_AMOUNT_ROUND_UP = DEFAULT_AMOUNT + 1;
    uint256 constant DEFAULT_AMOUNT_ROUND_DOWN = DEFAULT_AMOUNT - 1;

    function setUp() public {
        vault = VaultMockDeployer.deploy();
        router = new Router(IVault(address(vault)), new WETHTestToken());
        USDC = new ERC20TestToken("USDC", "USDC", 18);
        DAI = new ERC20TestToken("DAI", "DAI", 18);
        IRateProvider[] memory rateProviders = new IRateProvider[](2);

        pool = new PoolMock(
            IVault(address(vault)),
            "ERC20 Pool",
            "ERC20POOL",
            [address(DAI), address(USDC)].toMemoryArray().asIERC20(),
            rateProviders,
            true,
            365 days,
            address(0)
        );

        PoolConfig memory config = vault.getPoolConfig(address(pool));
        config.callbacks.shouldCallBeforeInitialize = true;
        config.callbacks.shouldCallAfterInitialize = true;
        vault.setConfig(address(pool), config);

        USDC.mint(bob, DEFAULT_AMOUNT);
        DAI.mint(bob, DEFAULT_AMOUNT);

        USDC.mint(alice, 2 * DEFAULT_AMOUNT);
        DAI.mint(alice, 2 * DEFAULT_AMOUNT);

        vm.startPrank(bob);

        USDC.approve(address(vault), type(uint256).max);
        DAI.approve(address(vault), type(uint256).max);

        vm.stopPrank();

        vm.startPrank(alice);

        USDC.approve(address(vault), type(uint256).max);
        DAI.approve(address(vault), type(uint256).max);

        vm.stopPrank();

        vm.label(alice, "alice");
        vm.label(bob, "bob");
        vm.label(address(USDC), "USDC");
        vm.label(address(DAI), "DAI");
    }

    function testNoRevertWithZeroConfig() public {
        PoolConfig memory config = vault.getPoolConfig(address(pool));
        config.callbacks.shouldCallBeforeInitialize = false;
        config.callbacks.shouldCallAfterInitialize = false;
        vault.setConfig(address(pool), config);

        pool.setFailOnBeforeInitializeCallback(true);
        pool.setFailOnAfterInitializeCallback(true);

        vm.prank(bob);
        router.initialize(
            address(pool),
            [address(DAI), address(USDC)].toMemoryArray().asIERC20(),
            [DEFAULT_AMOUNT, DEFAULT_AMOUNT].toMemoryArray(),
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
                [DEFAULT_AMOUNT, DEFAULT_AMOUNT].toMemoryArray(),
                bytes("0xff")
            )
        );
        router.initialize(
            address(pool),
            [address(DAI), address(USDC)].toMemoryArray().asIERC20(),
            [DEFAULT_AMOUNT, DEFAULT_AMOUNT].toMemoryArray(),
            0,
            false,
            bytes("0xff")
        );
    }

    function testOnBeforeInitializeCallbackRevert() public {
        pool.setFailOnBeforeInitializeCallback(true);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(CallbackFailed.selector));
        router.initialize(
            address(pool),
            [address(DAI), address(USDC)].toMemoryArray().asIERC20(),
            [DEFAULT_AMOUNT, DEFAULT_AMOUNT].toMemoryArray(),
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
                [DEFAULT_AMOUNT, DEFAULT_AMOUNT].toMemoryArray(),
                2 * DEFAULT_AMOUNT,
                bytes("0xff")
            )
        );
        router.initialize(
            address(pool),
            [address(DAI), address(USDC)].toMemoryArray().asIERC20(),
            [DEFAULT_AMOUNT, DEFAULT_AMOUNT].toMemoryArray(),
            0,
            false,
            bytes("0xff")
        );
    }

    function testOnAfterInitializeCallbackRevert() public {
        pool.setFailOnAfterInitializeCallback(true);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(CallbackFailed.selector));
        router.initialize(
            address(pool),
            [address(DAI), address(USDC)].toMemoryArray().asIERC20(),
            [DEFAULT_AMOUNT, DEFAULT_AMOUNT].toMemoryArray(),
            0,
            false,
            bytes("0xff")
        );
    }
}
