// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";

import { BasicAuthorizerMock } from "@balancer-labs/v3-solidity-utils/contracts/test/BasicAuthorizerMock.sol";
import { ERC20TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC20TestToken.sol";
import { WETHTestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/WETHTestToken.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";

import { PoolMock } from "../../contracts/test/PoolMock.sol";
import { VaultMock } from "../../contracts/test/VaultMock.sol";
import { Router } from "../../contracts/Router.sol";
import { FactoryWidePauseWindow } from "../../contracts/factories/FactoryWidePauseWindow.sol";
import { PoolFactoryMock } from "../../contracts/test/PoolFactoryMock.sol";

contract PoolPauseTest is Test {
    using ArrayHelpers for *;

    VaultMock vault;
    Router router;
    BasicAuthorizerMock authorizer;
    PoolMock pool;
    PoolMock unmanagedPool;
    PoolMock permissionlessPool;
    PoolMock infinityPool;
    PoolFactoryMock factory;
    ERC20TestToken USDC;
    ERC20TestToken DAI;
    address alice = vm.addr(1);
    address bob = vm.addr(2);
    address admin = vm.addr(3);
    IRateProvider[] rateProviders = new IRateProvider[](2);

    function setUp() public {
        authorizer = new BasicAuthorizerMock();
        vault = new VaultMock(authorizer, 30 days, 90 days);
        router = new Router(IVault(vault), new WETHTestToken());
        USDC = new ERC20TestToken("USDC", "USDC", 18);
        DAI = new ERC20TestToken("DAI", "DAI", 18);

        pool = new PoolMock(
            vault,
            "ERC20 Pool",
            "ERC20POOL",
            [address(DAI), address(USDC)].toMemoryArray().asIERC20(),
            rateProviders,
            true,
            365 days,
            admin
        );

        // Pass zero for the pause manager
        unmanagedPool = new PoolMock(
            vault,
            "ERC20 Pool",
            "ERC20POOL",
            [address(DAI), address(USDC)].toMemoryArray().asIERC20(),
            rateProviders,
            true,
            365 days,
            address(0)
        );

        permissionlessPool = new PoolMock(
            vault,
            "ERC20 Pool",
            "ERC20POOL",
            [address(DAI), address(USDC)].toMemoryArray().asIERC20(),
            rateProviders,
            true,
            0,
            address(0)
        );

        infinityPool = new PoolMock(
            vault,
            "ERC20 Pool",
            "ERC20POOL",
            [address(DAI), address(USDC)].toMemoryArray().asIERC20(),
            rateProviders,
            true,
            10000 days,
            address(0)
        );

        factory = new PoolFactoryMock(vault, 365 days);
    }

    function testPoolFactory() public {
        uint256 expectedEndTime = block.timestamp + 365 days;

        assertEq(factory.getPauseWindowDuration(), 365 days);
        assertEq(factory.getOriginalPauseWindowEndTime(), expectedEndTime);
        assertEq(factory.getNewPoolPauseWindowEndTime(), expectedEndTime);

        skip(365 days);
        assertEq(factory.getOriginalPauseWindowEndTime(), expectedEndTime);
        assertEq(factory.getNewPoolPauseWindowEndTime(), 0);
    }

    function testInvalidDuration() public {
        uint256 maxEndTimeTimestamp = type(uint32).max - block.timestamp;

        vm.expectRevert(FactoryWidePauseWindow.PoolPauseWindowDurationOverflow.selector);
        new PoolMock(
            vault,
            "ERC20 Pool",
            "ERC20POOL",
            [address(DAI), address(USDC)].toMemoryArray().asIERC20(),
            rateProviders,
            true,
            maxEndTimeTimestamp + 1,
            address(0)
        );
    }

    function testHasPauseManager() public {
        (, , , address pauseManager) = vault.getPoolPausedState(address(pool));
        assertEq(pauseManager, admin);

        (, , , pauseManager) = vault.getPoolPausedState(address(unmanagedPool));
        assertEq(pauseManager, address(0));
    }

    function testPauseManagerCanPause() public {
        // Pool is not paused
        assertFalse(vault.isPoolPaused(address(pool)));

        // pause manager can pause and unpause
        vm.prank(admin);
        vault.pausePool(address(pool));

        assertTrue(vault.isPoolPaused(address(pool)));

        vm.prank(admin);
        vault.unpausePool(address(pool));

        assertFalse(vault.isPoolPaused(address(pool)));
    }

    function testCannotPauseIfNotManager() public {
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IVault.SenderIsNotPauseManager.selector, address(pool)));
        vault.pausePool(address(pool));

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IVault.SenderIsNotPauseManager.selector, address(pool)));
        vault.unpausePool(address(pool));
    }

    function testGovernancePause() public {
        // Nice try, Bob!
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IAuthentication.SenderNotAllowed.selector));
        vault.pausePool(address(unmanagedPool));

        // Reluctantly authorize Bob
        bytes32 pausePoolRole = vault.getActionId(IVault.pausePool.selector);
        authorizer.grantRole(pausePoolRole, bob);

        vm.prank(bob);
        vault.pausePool(address(unmanagedPool));

        assertTrue(vault.isPoolPaused(address(unmanagedPool)));
    }

    function testCannotPausePermissionlessPool() public {
        // Authorize alice
        bytes32 pausePoolRole = vault.getActionId(IVault.pausePool.selector);
        authorizer.grantRole(pausePoolRole, alice);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IVault.PoolPauseWindowExpired.selector, address(permissionlessPool)));
        vault.pausePool(address(permissionlessPool));
    }

    function testInfinitePausePool() public {
        (, , , address pauseManager) = vault.getPoolPausedState(address(infinityPool));
        assertEq(pauseManager, address(0));

        // Authorize alice
        bytes32 pausePoolRole = vault.getActionId(IVault.pausePool.selector);
        authorizer.grantRole(pausePoolRole, alice);

        vm.prank(alice);
        vault.pausePool(address(infinityPool));

        assertTrue(vault.isPoolPaused(address(infinityPool)));
    }
}
