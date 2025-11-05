// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPCommon.sol";
import "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPool.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { LBPoolFactory } from "../../contracts/lbp/LBPoolFactory.sol";
import { BaseLBPFactory } from "../../contracts/lbp/BaseLBPFactory.sol";
import { WeightedLBPTest } from "./utils/WeightedLBPTest.sol";
import { LBPool } from "../../contracts/lbp/LBPool.sol";

contract LBPoolFactoryTest is WeightedLBPTest {
    using ArrayHelpers for *;

    uint32 internal defaultStartTime;
    uint32 internal defaultEndTime;

    function createPool() internal virtual override returns (address newPool, bytes memory poolArgs) {
        defaultStartTime = uint32(block.timestamp + DEFAULT_START_OFFSET);
        defaultEndTime = uint32(block.timestamp + DEFAULT_END_OFFSET);

        return _createLBPool(alice, defaultStartTime, defaultEndTime, DEFAULT_PROJECT_TOKENS_SWAP_IN);
    }

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
        vm.expectRevert(BaseLBPFactory.InvalidTrustedRouter.selector);
        new LBPoolFactory(
            vault,
            365 days,
            factoryVersion,
            poolVersion,
            ZERO_ADDRESS, // invalid trusted router address
            ZERO_ADDRESS // migration router address
        );
    }

    function testGetMaxBptLockDuration() public view {
        assertEq(lbPoolFactory.getMaxBptLockDuration(), MAX_BPT_LOCK_DURATION, "Wrong bpt lock duration");
    }

    function testGetMinReserveTokenMigrationWeight() public view {
        assertEq(
            lbPoolFactory.getMinReserveTokenMigrationWeight(),
            MIN_RESERVE_TOKEN_MIGRATION_WEIGHT,
            "Wrong reserve token weight"
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
        LBPCommonParams memory commonParams = LBPCommonParams({
            name: "LBPool",
            symbol: "LBP",
            owner: ZERO_ADDRESS,
            projectToken: projectToken,
            reserveToken: reserveToken,
            startTime: uint32(block.timestamp + DEFAULT_START_OFFSET),
            endTime: uint32(block.timestamp + DEFAULT_END_OFFSET),
            blockProjectTokenSwapsIn: true
        });

        // Create LBP params with owner set to zero address
        LBPParams memory params = LBPParams({
            projectTokenStartWeight: DEFAULT_WEIGHT,
            projectTokenEndWeight: DEFAULT_WEIGHT,
            reserveTokenStartWeight: DEFAULT_WEIGHT,
            reserveTokenEndWeight: DEFAULT_WEIGHT
        });

        vm.expectRevert(BaseLBPFactory.InvalidOwner.selector);
        lbPoolFactory.create(commonParams, params, swapFee, ZERO_BYTES32, address(0));
    }

    function testCreatePool() public {
        (pool, ) = _createLBPool(bob, uint32(block.timestamp + 100), uint32(block.timestamp + 200), true);
        initPool();

        // Verify pool was created and initialized correctly
        assertTrue(vault.isPoolRegistered(pool), "Pool not registered in the vault");
        assertTrue(vault.isPoolInitialized(pool), "Pool not initialized");

        LBPoolImmutableData memory data = ILBPool(pool).getLBPoolImmutableData();

        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(pool);
        (uint256[] memory decimalScalingFactors, ) = vault.getPoolTokenRates(address(pool));

        for (uint256 i = 0; i < tokens.length; ++i) {
            assertEq(address(data.tokens[i]), address(tokens[i]), "Token address mismatch");
            assertEq(data.decimalScalingFactors[i], decimalScalingFactors[i], "Decimal scaling factor mismatch");
            assertEq(data.startWeights[i], startWeights[i], "Wrong start weight");
            assertEq(data.endWeights[i], endWeights[i], "Wrong end weight");
        }

        assertEq(data.startTime, defaultStartTime, "Wrong start time");
        assertEq(data.endTime, defaultEndTime, "Wrong end time");
        assertEq(data.projectTokenIndex, projectIdx, "Wrong project token index");
        assertEq(data.reserveTokenIndex, reserveIdx, "Wrong reserve token index");
        assertEq(
            data.isProjectTokenSwapInBlocked,
            DEFAULT_PROJECT_TOKENS_SWAP_IN,
            "Wrong project token swap blocked flag"
        );

        assertEq(data.lockDurationAfterMigration, 0, "BPT lock duration should be zero");
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

        vm.expectEmit(false, true, true, true);
        emit BaseLBPFactory.MigrationParamsSet(
            address(0),
            initBptLockDuration,
            initBptPercentageToMigrate,
            initNewWeightProjectToken,
            initNewWeightReserveToken
        );

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

        LBPoolImmutableData memory data = ILBPool(pool).getLBPoolImmutableData();

        assertEq(data.migrationRouter, address(migrationRouter), "Migration router mismatch");
        assertEq(data.lockDurationAfterMigration, initBptLockDuration, "BPT lock duration mismatch");
        assertEq(data.bptPercentageToMigrate, initBptPercentageToMigrate, "Share to migrate mismatch");
        assertEq(data.migrationWeightProjectToken, initNewWeightProjectToken, "New weightProjectToken mismatch");
        assertEq(data.migrationWeightReserveToken, initNewWeightReserveToken, "New weightReserveToken mismatch");
        assertEq(vault.getPoolRoleAccounts(pool).poolCreator, bob, "Incorrect pool creator");
    }

    function testCreatePoolWithMigrationParamsButNoRouter() public {
        lbPoolFactory = deployLBPoolFactory(
            IVault(address(vault)),
            365 days,
            factoryVersion,
            poolVersion,
            address(router),
            address(0) // no migration router
        );

        // Set migration parameters
        uint256 initBptLockDuration = 30 days;
        uint256 initBptPercentageToMigrate = 50e16; // 50%
        uint256 initNewWeightProjectToken = 60e16; // 60%
        uint256 initNewWeightReserveToken = 40e16; // 40%

        vm.expectRevert(BaseLBPFactory.MigrationUnsupported.selector);
        (pool, ) = _createLBPoolWithMigration(
            bob,
            initBptLockDuration,
            initBptPercentageToMigrate,
            initNewWeightProjectToken,
            initNewWeightReserveToken
        );
    }

    function testCreatePoolWithInvalidMigrationWeights() public {
        uint256 initBptLockDuration = 30 days;
        uint256 initBptPercentageToMigrate = 50e16; // 50%
        uint256 minReserveTokenWeight = 20e16; // 20%
        uint256 maxProjectTokenWeight = 100e16 - minReserveTokenWeight;

        vm.expectRevert(BaseLBPFactory.InvalidMigrationWeights.selector);
        _createLBPoolWithMigration(address(0), initBptLockDuration, initBptPercentageToMigrate, 0, 100e16);

        vm.expectRevert(BaseLBPFactory.InvalidMigrationWeights.selector);
        _createLBPoolWithMigration(address(0), initBptLockDuration, initBptPercentageToMigrate, 100e16, 0);

        vm.expectRevert(BaseLBPFactory.InvalidMigrationWeights.selector);
        _createLBPoolWithMigration(
            address(0),
            initBptLockDuration,
            initBptPercentageToMigrate,
            maxProjectTokenWeight + 1,
            minReserveTokenWeight - 1
        );

        vm.expectRevert(BaseLBPFactory.InvalidMigrationWeights.selector);
        _createLBPoolWithMigration(address(0), initBptLockDuration, initBptPercentageToMigrate, 100e16, 100e16);

        vm.expectRevert(BaseLBPFactory.InvalidMigrationWeights.selector);
        _createLBPoolWithMigration(address(0), initBptLockDuration, initBptPercentageToMigrate, 100e16, 50e16);
    }

    function testCreatePoolWithInvalidBptPercentageToMigrateTooHigh() public {
        uint256 initBptLockDuration = 30 days;
        uint256 initNewWeightProjectToken = 60e16; // 60%
        uint256 initNewWeightReserveToken = 40e16; // 40%

        // BPT percentage to migrate cannot be zero
        vm.expectRevert(BaseLBPFactory.InvalidBptPercentageToMigrate.selector);
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
        vm.expectRevert(BaseLBPFactory.InvalidBptPercentageToMigrate.selector);
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

        vm.expectRevert(BaseLBPFactory.InvalidBptLockDuration.selector);
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

        vm.expectRevert(BaseLBPFactory.InvalidBptLockDuration.selector);
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

    function _createLBPoolWithMigration(
        address poolCreator,
        uint256 lockDurationAfterMigration,
        uint256 bptPercentageToMigrate,
        uint256 migrationWeightProjectToken,
        uint256 migrationWeightReserveToken
    ) internal override returns (address newPool, bytes memory poolArgs) {
        string memory name = "LBPool";
        string memory symbol = "LBP";

        LBPCommonParams memory lbpCommonParams = LBPCommonParams({
            name: name,
            symbol: symbol,
            owner: bob,
            projectToken: projectToken,
            reserveToken: reserveToken,
            startTime: uint32(block.timestamp + DEFAULT_START_OFFSET),
            endTime: uint32(block.timestamp + DEFAULT_END_OFFSET),
            blockProjectTokenSwapsIn: DEFAULT_PROJECT_TOKENS_SWAP_IN
        });

        MigrationParams memory migrationParams = MigrationParams({
            lockDurationAfterMigration: lockDurationAfterMigration,
            bptPercentageToMigrate: bptPercentageToMigrate,
            migrationWeightProjectToken: migrationWeightProjectToken,
            migrationWeightReserveToken: migrationWeightReserveToken
        });

        LBPParams memory lbpParams = LBPParams({
            projectTokenStartWeight: startWeights[projectIdx],
            reserveTokenStartWeight: startWeights[reserveIdx],
            projectTokenEndWeight: endWeights[projectIdx],
            reserveTokenEndWeight: endWeights[reserveIdx]
        });

        FactoryParams memory factoryParams = FactoryParams({
            vault: vault,
            trustedRouter: address(router),
            migrationRouter: address(migrationRouter),
            poolVersion: poolVersion
        });

        // Copy to local variable to free up parameter stack slot before operations that create temporaries.
        uint256 salt = _saltCounter++;
        address poolCreator_ = poolCreator;

        newPool = lbPoolFactory.createWithMigration(
            lbpCommonParams,
            migrationParams,
            lbpParams,
            swapFee,
            bytes32(salt),
            poolCreator_
        );

        poolArgs = abi.encode(lbpCommonParams, migrationParams, lbpParams, factoryParams);

        return (newPool, poolArgs);
    }

    function _createLBPool(
        address poolCreator,
        uint32 startTime,
        uint32 endTime,
        bool blockProjectTokenSwapsIn
    ) internal override returns (address newPool, bytes memory poolArgs) {
        return
            _createLBPoolWithCustomWeights(
                poolCreator,
                startWeights[projectIdx],
                startWeights[reserveIdx],
                endWeights[projectIdx],
                endWeights[reserveIdx],
                startTime,
                endTime,
                blockProjectTokenSwapsIn
            );
    }
}
