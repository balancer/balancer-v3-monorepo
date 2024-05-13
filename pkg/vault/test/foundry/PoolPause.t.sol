// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { TokenConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";

import { PoolMock } from "../../contracts/test/PoolMock.sol";
import { FactoryWidePauseWindow } from "../../contracts/factories/FactoryWidePauseWindow.sol";
import { PoolFactoryMock } from "../../contracts/test/PoolFactoryMock.sol";
import { PoolConfigBits, PoolConfigLib } from "../../contracts/lib/PoolConfigLib.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract PoolPauseTest is BaseVaultTest {
    using ArrayHelpers for *;

    PoolMock internal unmanagedPool;
    PoolMock internal permissionlessPool;
    PoolMock internal infinityPool;

    PoolFactoryMock internal factory;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        TokenConfig[] memory tokenConfig = vault.buildTokenConfig(
            [address(dai), address(usdc)].toMemoryArray().asIERC20()
        );

        PoolRoleAccounts memory defaultRoleAccounts = PoolRoleAccounts({
            pauseManager: address(0),
            swapFeeManager: address(0),
            poolCreator: address(0)
        });

        PoolRoleAccounts memory adminRoleAccounts = PoolRoleAccounts({
            pauseManager: admin,
            swapFeeManager: address(0),
            poolCreator: address(0)
        });

        pool = address(new PoolMock(IVault(address(vault)), "ERC20 Pool", "ERC20POOL"));

        factoryMock.registerGeneralTestPool(address(pool), tokenConfig, 0, 365 days, adminRoleAccounts);

        // Pass zero for the pause manager
        unmanagedPool = new PoolMock(IVault(address(vault)), "ERC20 Pool", "ERC20POOL");

        factoryMock.registerGeneralTestPool(address(unmanagedPool), tokenConfig, 0, 365 days, defaultRoleAccounts);

        permissionlessPool = new PoolMock(IVault(address(vault)), "ERC20 Pool", "ERC20POOL");

        factoryMock.registerGeneralTestPool(address(permissionlessPool), tokenConfig, 0, 0, defaultRoleAccounts);

        infinityPool = new PoolMock(IVault(address(vault)), "ERC20 Pool", "ERC20POOL");

        factoryMock.registerGeneralTestPool(address(infinityPool), tokenConfig, 0, 10000 days, defaultRoleAccounts);

        factory = new PoolFactoryMock(IVault(address(vault)), 365 days);
    }

    function testPoolFactory() public {
        uint256 expectedEndTime = block.timestamp + 365 days;

        assertEq(factory.getPauseWindowDuration(), 365 days, "Wrong pause window duration");
        assertEq(factory.getOriginalPauseWindowEndTime(), expectedEndTime, "Wrong original pause window end time");
        assertEq(factory.getNewPoolPauseWindowEndTime(), expectedEndTime, "Wrong new pool pause window end time");

        skip(365 days);
        assertEq(
            factory.getOriginalPauseWindowEndTime(),
            expectedEndTime,
            "Wrong original pause window end time a year later"
        );
        assertEq(factory.getNewPoolPauseWindowEndTime(), 0, "New pool pause window end time non-zero");
    }

    function testInvalidDuration() public {
        uint256 maxDuration = type(uint32).max - block.timestamp;

        vm.expectRevert(FactoryWidePauseWindow.PoolPauseWindowDurationOverflow.selector);
        new PoolFactoryMock(vault, maxDuration + 1);
    }

    function testHasPauseManager() public {
        (, , , address pauseManager) = vault.getPoolPausedState(address(pool));
        assertEq(pauseManager, admin, "Pause manager is not admin");

        (, , , pauseManager) = vault.getPoolPausedState(address(unmanagedPool));
        assertEq(pauseManager, address(0), "Pause manager non-zero");
    }

    function testPauseManagerCanPause() public {
        // Pool is not paused
        require(vault.isPoolPaused(address(pool)) == false, "Vault is already paused");

        // pause manager can pause and unpause
        vm.prank(admin);
        vault.pausePool(address(pool));

        assertTrue(vault.isPoolPaused(address(pool)), "Vault not paused");

        vm.prank(admin);
        vault.unpausePool(address(pool));

        assertFalse(vault.isPoolPaused(address(pool)), "Vault is still paused after unpause");
    }

    function testCannotPauseIfNotManager() public {
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IAuthentication.SenderNotAllowed.selector));
        vault.pausePool(address(pool));

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IAuthentication.SenderNotAllowed.selector));
        vault.unpausePool(address(pool));
    }

    function testGovernancePause() public {
        // Nice try, Bob!
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IAuthentication.SenderNotAllowed.selector));
        vault.pausePool(address(unmanagedPool));

        // Reluctantly authorize Bob
        bytes32 pausePoolRole = vault.getActionId(IVaultAdmin.pausePool.selector);
        authorizer.grantRole(pausePoolRole, bob);

        vm.prank(bob);
        vault.pausePool(address(unmanagedPool));

        assertTrue(vault.isPoolPaused(address(unmanagedPool)), "Pool not paused");
    }

    function testCannotPausePermissionlessPool() public {
        // Authorize alice
        bytes32 pausePoolRole = vault.getActionId(IVaultAdmin.pausePool.selector);
        authorizer.grantRole(pausePoolRole, alice);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IVaultErrors.PoolPauseWindowExpired.selector, address(permissionlessPool))
        );
        vault.pausePool(address(permissionlessPool));
    }

    function testInfinitePausePool() public {
        (, , , address pauseManager) = vault.getPoolPausedState(address(infinityPool));
        require(pauseManager == address(0), "Pause manager non-zero");

        // Authorize alice
        bytes32 pausePoolRole = vault.getActionId(IVaultAdmin.pausePool.selector);
        authorizer.grantRole(pausePoolRole, alice);

        vm.prank(alice);
        vault.pausePool(address(infinityPool));

        assertTrue(vault.isPoolPaused(address(infinityPool)), "Pool not paused");
    }
}
