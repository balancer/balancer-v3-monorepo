// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { ILBPMigrationRouter } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPMigrationRouter.sol";
import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { ILBPool, LBPParams } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPool.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";

import { LBPoolFactory } from "../../contracts/lbp/LBPoolFactory.sol";
import { LBPool } from "../../contracts/lbp/LBPool.sol";
import { BaseLBPTest } from "./utils/BaseLBPTest.sol";

contract LBPoolFactoryTest is BaseLBPTest {
    using ArrayHelpers for *;

    uint256 private constant _DEFAULT_WEIGHT = 50e16;

    function testPoolRegistrationOnCreate() public view {
        // Verify pool was registered in the factory.
        assertTrue(lbPoolFactory.isPoolFromFactory(pool), "Pool is not from LBP factory");

        // Verify pool was created and initialized correctly in the vault by the factory.
        assertTrue(vault.isPoolRegistered(pool), "Pool not registered in the vault");
        assertTrue(vault.isPoolInitialized(pool), "Pool not initialized");
    }

    function testPoolInitialization() public view {
        (IERC20[] memory tokens, , uint256[] memory balancesRaw, ) = vault.getPoolTokenInfo(pool);

        assertEq(address(tokens[projectIdx]), address(projectToken), "Project token mismatch");
        assertEq(address(tokens[reserveIdx]), address(reserveToken), "Reserve token mismatch");

        assertEq(balancesRaw[projectIdx], poolInitAmount, "Balances of project token mismatch");
        assertEq(balancesRaw[reserveIdx], poolInitAmount, "Balances of reserve token mismatch");
    }

    function testGetPoolVersion() public view {
        assertEq(lbPoolFactory.getPoolVersion(), poolVersion, "Pool version mismatch");
    }

    function testInvalidTrustedRouter() public {
        vm.expectRevert(LBPoolFactory.InvalidTrustedRouter.selector);
        new LBPoolFactory(
            vault,
            365 days,
            factoryVersion,
            poolVersion,
            address(0), // invalid trusted router address
            address(0) // migration router address
        );
    }

    function testGetTrustedRouter() public view {
        assertEq(lbPoolFactory.getTrustedRouter(), address(router), "Wrong trusted router");
    }

    function testGetMigrationRouter() public view {
        assertEq(lbPoolFactory.getMigrationRouter(), address(migrationRouter), "Wrong migration router");
    }

    function testFactoryPausedState() public view {
        uint32 pauseWindowDuration = lbPoolFactory.getPauseWindowDuration();
        assertEq(pauseWindowDuration, 365 days);
    }

    function testCreatePoolWithInvalidOwner() public {
        // Create LBP params with owner set to zero address
        LBPParams memory params = LBPParams({
            owner: address(0),
            projectToken: projectToken,
            reserveToken: reserveToken,
            startTime: uint32(block.timestamp + DEFAULT_START_OFFSET),
            endTime: uint32(block.timestamp + DEFAULT_END_OFFSET),
            projectTokenStartWeight: _DEFAULT_WEIGHT,
            projectTokenEndWeight: _DEFAULT_WEIGHT,
            reserveTokenStartWeight: _DEFAULT_WEIGHT,
            reserveTokenEndWeight: _DEFAULT_WEIGHT,
            blockProjectTokenSwapsIn: true
        });

        vm.expectRevert(LBPoolFactory.InvalidOwner.selector);
        lbPoolFactory.create("LBPool", "LBP", params, swapFee, bytes32(0));
    }

    function testCreatePool() public {
        (pool, ) = _createLBPool(uint32(block.timestamp + 100), uint32(block.timestamp + 200), true);
        initPool();

        // Verify pool was created and initialized correctly
        assertTrue(vault.isPoolRegistered(pool), "Pool not registered in the vault");
        assertTrue(vault.isPoolInitialized(pool), "Pool not initialized");

        (
            address migrationRouter,
            uint256 bptLockDuration,
            uint256 shareToMigrate,
            uint256 weight0,
            uint256 weight1
        ) = LBPool(pool).getMigrationParams();

        assertEq(bptLockDuration, 0, "BPT lock duration should be zero");
        assertEq(shareToMigrate, 0, "Share to migrate should be zero");
        assertEq(weight0, 0, "Weight0 should be zero");
        assertEq(weight1, 0, "Weight1 should be zero");
        assertEq(migrationRouter, address(0), "Migration router should be zero address");
    }

    function testCreatePoolWithMigrationParams() public {
        // Set migration parameters
        uint256 initBptLockDuration = 30 days;
        uint256 initShareToMigrate = 50e16; // 50%
        uint256 initNewWeight0 = 60e16; // 60%
        uint256 initNewWeight1 = 40e16; // 40%

        (pool, ) = _createLBPoolWithMigration(initBptLockDuration, initShareToMigrate, initNewWeight0, initNewWeight1);
        initPool();

        assertTrue(vault.isPoolRegistered(pool), "Pool not registered in the vault");
        assertTrue(vault.isPoolInitialized(pool), "Pool not initialized");

        (
            address migrationRouter,
            uint256 bptLockDuration,
            uint256 shareToMigrate,
            uint256 weight0,
            uint256 weight1
        ) = LBPool(pool).getMigrationParams();

        assertEq(migrationRouter, address(migrationRouter), "Migration router mismatch");
        assertEq(bptLockDuration, initBptLockDuration, "BPT lock duration mismatch");
        assertEq(shareToMigrate, initShareToMigrate, "Share to migrate mismatch");
        assertEq(weight0, initNewWeight0, "New weight0 mismatch");
        assertEq(weight1, initNewWeight1, "New weight1 mismatch");
    }

    function testCreatePoolWithInvalidMigrationParams() public {
        uint256 initBptLockDuration = 30 days;
        uint256 initShareToMigrate = 50e16; // 50%

        vm.expectRevert(LBPoolFactory.InvalidMigrationWeights.selector);
        _createLBPoolWithMigration(initBptLockDuration, initShareToMigrate, 0, 100e16);

        vm.expectRevert(LBPoolFactory.InvalidMigrationWeights.selector);
        _createLBPoolWithMigration(initBptLockDuration, initShareToMigrate, 100e16, 0);

        vm.expectRevert(LBPoolFactory.InvalidMigrationWeights.selector);
        _createLBPoolWithMigration(initBptLockDuration, initShareToMigrate, 100e16, 100e16);

        vm.expectRevert(LBPoolFactory.InvalidMigrationWeights.selector);
        _createLBPoolWithMigration(initBptLockDuration, initShareToMigrate, 100e16, 50e16);
    }

    function testAddLiquidityPermission() public {
        (pool, ) = _createLBPool(uint32(block.timestamp + 100), uint32(block.timestamp + 200), true);
        initPool();

        // Try to add to the pool without permission.
        vm.expectRevert(IVaultErrors.BeforeAddLiquidityHookFailed.selector);
        router.addLiquidityProportional(pool, [DEFAULT_AMOUNT, DEFAULT_AMOUNT].toMemoryArray(), 0, false, bytes(""));

        // The owner is allowed to add.
        vm.prank(bob);
        router.addLiquidityProportional(pool, [DEFAULT_AMOUNT, DEFAULT_AMOUNT].toMemoryArray(), 0, false, bytes(""));
    }

    function testDonationNotAllowed() public {
        (pool, ) = _createLBPool(uint32(block.timestamp + 100), uint32(block.timestamp + 200), true);
        initPool();

        // Try to donate to the pool
        vm.expectRevert(IVaultErrors.BeforeAddLiquidityHookFailed.selector);
        router.donate(pool, [poolInitAmount, poolInitAmount].toMemoryArray(), false, bytes(""));
    }

    function testSetSwapFeeNoPermission() public {
        // The LBP Factory only allows the owner (a.k.a. bob) to set the static swap fee percentage of the pool.
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        vault.setStaticSwapFeePercentage(pool, 2.5e16);
    }

    function testSetSwapFee() public {
        uint256 newSwapFee = 2.5e16; // 2.5%

        // Starts out at the default
        assertEq(vault.getStaticSwapFeePercentage(pool), swapFee);

        vm.prank(bob);
        vault.setStaticSwapFeePercentage(pool, newSwapFee);

        assertEq(vault.getStaticSwapFeePercentage(pool), newSwapFee);
    }
}
