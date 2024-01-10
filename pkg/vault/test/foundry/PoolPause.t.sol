// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultMain } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultMain.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";

import { PoolMock } from "../../contracts/test/PoolMock.sol";
import { FactoryWidePauseWindow } from "../../contracts/factories/FactoryWidePauseWindow.sol";
import { PoolFactoryMock } from "../../contracts/test/PoolFactoryMock.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract PoolPauseTest is BaseVaultTest {
    using ArrayHelpers for *;

    PoolMock internal unmanagedPool;
    PoolMock internal permissionlessPool;
    PoolMock internal infinityPool;

    PoolFactoryMock internal factory;
    IRateProvider[] internal rateProviders;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        rateProviders = new IRateProvider[](2);

        pool = address(
            new PoolMock(
                IVault(address(vault)),
                "ERC20 Pool",
                "ERC20POOL",
                [address(dai), address(usdc)].toMemoryArray().asIERC20(),
                new IRateProvider[](2),
                true,
                365 days,
                admin
            )
        );

        // Pass zero for the pause manager
        unmanagedPool = new PoolMock(
            IVault(address(vault)),
            "ERC20 Pool",
            "ERC20POOL",
            [address(dai), address(usdc)].toMemoryArray().asIERC20(),
            rateProviders,
            true,
            365 days,
            address(0)
        );

        permissionlessPool = new PoolMock(
            IVault(address(vault)),
            "ERC20 Pool",
            "ERC20POOL",
            [address(dai), address(usdc)].toMemoryArray().asIERC20(),
            rateProviders,
            true,
            0,
            address(0)
        );

        infinityPool = new PoolMock(
            IVault(address(vault)),
            "ERC20 Pool",
            "ERC20POOL",
            [address(dai), address(usdc)].toMemoryArray().asIERC20(),
            rateProviders,
            true,
            10000 days,
            address(0)
        );

        factory = new PoolFactoryMock(IVault(address(vault)), 365 days);
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
            IVault(address(vault)),
            "ERC20 Pool",
            "ERC20POOL",
            [address(dai), address(usdc)].toMemoryArray().asIERC20(),
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
        vm.expectRevert(abi.encodeWithSelector(IVaultMain.SenderIsNotPauseManager.selector, address(pool)));
        vault.pausePool(address(pool));

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IVaultMain.SenderIsNotPauseManager.selector, address(pool)));
        vault.unpausePool(address(pool));
    }

    function testGovernancePause() public {
        // Nice try, Bob!
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IAuthentication.SenderNotAllowed.selector));
        vault.pausePool(address(unmanagedPool));

        // Reluctantly authorize Bob
        bytes32 pausePoolRole = vault.getActionId(IVaultMain.pausePool.selector);
        authorizer.grantRole(pausePoolRole, bob);

        vm.prank(bob);
        vault.pausePool(address(unmanagedPool));

        assertTrue(vault.isPoolPaused(address(unmanagedPool)));
    }

    function testCannotPausePermissionlessPool() public {
        // Authorize alice
        bytes32 pausePoolRole = vault.getActionId(IVaultMain.pausePool.selector);
        authorizer.grantRole(pausePoolRole, alice);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IVaultMain.PoolPauseWindowExpired.selector, address(permissionlessPool)));
        vault.pausePool(address(permissionlessPool));
    }

    function testInfinitePausePool() public {
        (, , , address pauseManager) = vault.getPoolPausedState(address(infinityPool));
        assertEq(pauseManager, address(0));

        // Authorize alice
        bytes32 pausePoolRole = vault.getActionId(IVaultMain.pausePool.selector);
        authorizer.grantRole(pausePoolRole, alice);

        vm.prank(alice);
        vault.pausePool(address(infinityPool));

        assertTrue(vault.isPoolPaused(address(infinityPool)));
    }
}
