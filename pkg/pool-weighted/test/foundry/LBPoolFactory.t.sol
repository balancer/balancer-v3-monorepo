// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {
    ILBPool,
    LBPParams,
    LBPoolImmutableData
} from "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPool.sol";
import { ILBPMigrationRouter } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPMigrationRouter.sol";
import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

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
            ZERO_ADDRESS, // invalid trusted router address
            ZERO_ADDRESS // migration router address
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
            owner: ZERO_ADDRESS,
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
        lbPoolFactory.create("LBPool", "LBP", params, swapFee, ZERO_BYTES32, address(0));
    }

    function testCreatePool() public {
        (pool, ) = _createLBPool(bob, uint32(block.timestamp + 100), uint32(block.timestamp + 200), true);
        initPool();

        // Verify pool was created and initialized correctly
        assertTrue(vault.isPoolRegistered(pool), "Pool not registered in the vault");
        assertTrue(vault.isPoolInitialized(pool), "Pool not initialized");

        LBPoolImmutableData memory data = LBPool(pool).getLBPoolImmutableData();

        assertEq(data.bptLockDuration, 0, "BPT lock duration should be zero");
        assertEq(data.bptPercentageToMigrate, 0, "Share to migrate should be zero");
        assertEq(data.migrationWeightProjectToken, 0, "Project token weight should be zero");
        assertEq(data.migrationWeightReserveToken, 0, "Reserve token weight should be zero");
        assertEq(data.migrationRouter, ZERO_ADDRESS, "Migration router should be zero address");

        assertEq(vault.getPoolRoleAccounts(pool).poolCreator, bob, "Incorrect pool creator");
    }

    function testCreatePoolWithMigrationParams() public {
        // Set migration parameters
        uint256 initBptLockDuration = 30 days;
        uint256 initBptPercentageToMigrate = 50e16; // 50%
        uint256 initNewWeightProjectToken = 60e16; // 60%
        uint256 initNewWeightReserveToken = 40e16; // 40%

        (pool, ) = _createLBPoolWithMigration(
            bob,
            initBptLockDuration,
            initBptPercentageToMigrate,
            initNewWeightProjectToken,
            initNewWeightReserveToken
        );
        initPool();

        assertTrue(vault.isPoolRegistered(pool), "Pool not registered in the vault");
        assertTrue(vault.isPoolInitialized(pool), "Pool not initialized");

        LBPoolImmutableData memory data = LBPool(pool).getLBPoolImmutableData();

        assertEq(data.migrationRouter, address(migrationRouter), "Migration router mismatch");
        assertEq(data.bptLockDuration, initBptLockDuration, "BPT lock duration mismatch");
        assertEq(data.bptPercentageToMigrate, initBptPercentageToMigrate, "Share to migrate mismatch");
        assertEq(data.migrationWeightProjectToken, initNewWeightProjectToken, "New weightProjectToken mismatch");
        assertEq(data.migrationWeightReserveToken, initNewWeightReserveToken, "New weightReserveToken mismatch");
        assertEq(vault.getPoolRoleAccounts(pool).poolCreator, bob, "Incorrect pool creator");
    }

    function testCreatePoolWithInvalidMigrationWeights() public {
        uint256 initBptLockDuration = 30 days;
        uint256 initBptPercentageToMigrate = 50e16; // 50%
        uint256 minReserveTokenWeight = 20e16; // 20%
        uint256 maxProjectTokenWeight = 100e16 - minReserveTokenWeight;

        vm.expectRevert(LBPoolFactory.InvalidMigrationWeights.selector);
        _createLBPoolWithMigration(address(0), initBptLockDuration, initBptPercentageToMigrate, 0, 100e16);

        vm.expectRevert(LBPoolFactory.InvalidMigrationWeights.selector);
        _createLBPoolWithMigration(address(0), initBptLockDuration, initBptPercentageToMigrate, 100e16, 0);

        vm.expectRevert(LBPoolFactory.InvalidMigrationWeights.selector);
        _createLBPoolWithMigration(
            address(0),
            initBptLockDuration,
            initBptPercentageToMigrate,
            maxProjectTokenWeight + 1,
            minReserveTokenWeight - 1
        );

        vm.expectRevert(LBPoolFactory.InvalidMigrationWeights.selector);
        _createLBPoolWithMigration(address(0), initBptLockDuration, initBptPercentageToMigrate, 100e16, 100e16);

        vm.expectRevert(LBPoolFactory.InvalidMigrationWeights.selector);
        _createLBPoolWithMigration(address(0), initBptLockDuration, initBptPercentageToMigrate, 100e16, 50e16);
    }

    function testCreatePoolWithInvalidBptPercentageToMigrateTooHigh() public {
        uint256 initBptLockDuration = 30 days;
        uint256 initNewWeightProjectToken = 60e16; // 60%
        uint256 initNewWeightReserveToken = 40e16; // 40%

        // BPT percentage to migrate cannot be zero
        vm.expectRevert(LBPoolFactory.InvalidBptPercentageToMigrate.selector);
        _createLBPoolWithMigration(
            address(0),
            initBptLockDuration,
            FixedPoint.ONE + 1,
            initNewWeightProjectToken,
            initNewWeightReserveToken
        );
    }

    function testCreatePoolWithInvalidBptPercentageToMigrateZero() public {
        uint256 initBptLockDuration = 30 days;
        uint256 initNewWeightProjectToken = 60e16; // 60%
        uint256 initNewWeightReserveToken = 40e16; // 40%

        // BPT percentage to migrate cannot be zero
        vm.expectRevert(LBPoolFactory.InvalidBptPercentageToMigrate.selector);
        _createLBPoolWithMigration(
            address(0),
            initBptLockDuration,
            0,
            initNewWeightProjectToken,
            initNewWeightReserveToken
        );
    }

    function testCreatePoolWithInvalidBptLockDurationTooHigh() public {
        uint256 initBptPercentageToMigrate = 50e16; // 50%
        uint256 initNewWeightProjectToken = 60e16; // 60%
        uint256 initNewWeightReserveToken = 40e16; // 40%

        vm.expectRevert(LBPoolFactory.InvalidBptLockDuration.selector);
        _createLBPoolWithMigration(
            address(0),
            366 days,
            initBptPercentageToMigrate,
            initNewWeightProjectToken,
            initNewWeightReserveToken
        );
    }

    function testCreatePoolWithInvalidBptLockDurationTooZero() public {
        uint256 initBptPercentageToMigrate = 50e16; // 50%
        uint256 initNewWeightProjectToken = 60e16; // 60%
        uint256 initNewWeightReserveToken = 40e16; // 40%

        vm.expectRevert(LBPoolFactory.InvalidBptLockDuration.selector);
        _createLBPoolWithMigration(
            address(0),
            0,
            initBptPercentageToMigrate,
            initNewWeightProjectToken,
            initNewWeightReserveToken
        );
    }

    function testAddLiquidityPermission() public {
        (pool, ) = _createLBPool(address(0), uint32(block.timestamp + 100), uint32(block.timestamp + 200), true);
        initPool();

        // Try to add to the pool without permission.
        vm.expectRevert(IVaultErrors.BeforeAddLiquidityHookFailed.selector);
        router.addLiquidityProportional(pool, [DEFAULT_AMOUNT, DEFAULT_AMOUNT].toMemoryArray(), 0, false, bytes(""));

        // The owner is allowed to add.
        vm.prank(bob);
        router.addLiquidityProportional(pool, [DEFAULT_AMOUNT, DEFAULT_AMOUNT].toMemoryArray(), 0, false, bytes(""));
    }

    function testDonationNotAllowed() public {
        (pool, ) = _createLBPool(address(0), uint32(block.timestamp + 100), uint32(block.timestamp + 200), true);
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
