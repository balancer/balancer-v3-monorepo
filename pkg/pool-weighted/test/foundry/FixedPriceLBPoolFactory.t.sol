// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import "@balancer-labs/v3-interfaces/contracts/pool-weighted/IFixedPriceLBPool.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPCommon.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { FixedPriceLBPoolContractsDeployer } from "./utils/FixedPriceLBPoolContractsDeployer.sol";
import { FixedPriceLBPoolFactory } from "../../contracts/lbp/FixedPriceLBPoolFactory.sol";
import { FixedPriceLBPool } from "../../contracts/lbp/FixedPriceLBPool.sol";
import { BaseLBPFactory } from "../../contracts/lbp/BaseLBPFactory.sol";
import { LBPValidation } from "../../contracts/lbp/LBPValidation.sol";
import { BaseLBPTest } from "./utils/BaseLBPTest.sol";

contract FixedPriceLBPoolFactoryTest is BaseLBPTest, FixedPriceLBPoolContractsDeployer {
    using ArrayHelpers for *;

    uint256 internal constant DEFAULT_RATE = FixedPoint.ONE;

    // Bounds on the project token rate.
    uint256 private constant MIN_PROJECT_TOKEN_RATE = FixedPoint.ONE / 10_000;
    uint256 private constant MAX_PROJECT_TOKEN_RATE = FixedPoint.ONE * 10_000;

    FixedPriceLBPoolFactory internal lbPoolFactory;

    uint32 internal defaultStartTime;
    uint32 internal defaultEndTime;

    function setUp() public virtual override {
        super.setUp();
    }

    function createPoolFactory() internal virtual override returns (address) {
        lbPoolFactory = deployFixedPriceLBPoolFactory(
            IVault(address(vault)),
            365 days,
            factoryVersion,
            poolVersion,
            address(router),
            address(migrationRouter)
        );
        vm.label(address(lbPoolFactory), "Fixed Price LB pool factory");

        return address(lbPoolFactory);
    }

    function createPool() internal virtual override returns (address newPool, bytes memory poolArgs) {
        defaultStartTime = uint32(block.timestamp + DEFAULT_START_OFFSET);
        defaultEndTime = uint32(block.timestamp + DEFAULT_END_OFFSET);

        return _createFixedPriceLBPool(alice, defaultStartTime, defaultEndTime, DEFAULT_PROJECT_TOKENS_SWAP_IN);
    }

    function initPool() internal virtual override {
        uint256[] memory initAmounts = new uint256[](2);
        initAmounts[projectIdx] = poolInitAmount;
        // Should have zero reserve if it's a buy-only sale.
        initAmounts[reserveIdx] = DEFAULT_PROJECT_TOKENS_SWAP_IN ? 0 : poolInitAmount;

        vm.startPrank(bob); // Bob is the owner of the pool.
        _initPool(pool, initAmounts, 0);
        vm.stopPrank();
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

        uint256 reserveInitAmount = DEFAULT_PROJECT_TOKENS_SWAP_IN ? 0 : poolInitAmount;

        assertEq(balancesRaw[projectIdx], poolInitAmount, "Balances of project token mismatch");
        assertEq(balancesRaw[reserveIdx], reserveInitAmount, "Balances of reserve token mismatch");
    }

    function testGetPoolVersion() public view {
        assertEq(lbPoolFactory.getPoolVersion(), poolVersion, "Pool version mismatch");
    }

    function testInvalidTrustedRouter() public {
        vm.expectRevert(BaseLBPFactory.InvalidTrustedRouter.selector);
        new FixedPriceLBPoolFactory(
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
            name: "FixedPriceLBPool",
            symbol: "FLBP",
            owner: ZERO_ADDRESS,
            projectToken: projectToken,
            reserveToken: reserveToken,
            startTime: uint32(block.timestamp + DEFAULT_START_OFFSET),
            endTime: uint32(block.timestamp + DEFAULT_END_OFFSET),
            blockProjectTokenSwapsIn: true
        });

        vm.expectRevert(LBPValidation.InvalidOwner.selector);
        lbPoolFactory.create(commonParams, DEFAULT_RATE, swapFee, ZERO_BYTES32, address(0));
    }

    function testCreatePool() public {
        (pool, ) = _createFixedPriceLBPool(bob, uint32(block.timestamp + 100), uint32(block.timestamp + 200), true);
        initPool();

        // Verify pool was created and initialized correctly
        assertTrue(vault.isPoolRegistered(pool), "Pool not registered in the vault");
        assertTrue(vault.isPoolInitialized(pool), "Pool not initialized");

        FixedPriceLBPoolImmutableData memory data = IFixedPriceLBPool(pool).getFixedPriceLBPoolImmutableData();

        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(pool);
        (uint256[] memory decimalScalingFactors, ) = vault.getPoolTokenRates(address(pool));

        for (uint256 i = 0; i < tokens.length; ++i) {
            assertEq(address(data.tokens[i]), address(tokens[i]), "Token address mismatch");
            assertEq(data.decimalScalingFactors[i], decimalScalingFactors[i], "Decimal scaling factor mismatch");
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

        assertEq(data.projectTokenRate, DEFAULT_RATE, "Wrong project token rate");
        assertEq(data.migrationRouter, address(0), "Migration router not zero");

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

        (pool, ) = _createFixedPriceLBPoolWithMigration(
            bob,
            initBptLockDuration,
            initBptPercentageToMigrate,
            initNewWeightProjectToken,
            initNewWeightReserveToken
        );
        initPool();

        assertTrue(vault.isPoolRegistered(pool), "Pool not registered in the vault");
        assertTrue(vault.isPoolInitialized(pool), "Pool not initialized");

        FixedPriceLBPoolImmutableData memory data = IFixedPriceLBPool(pool).getFixedPriceLBPoolImmutableData();

        assertEq(data.migrationRouter, address(migrationRouter), "Migration router mismatch");
        assertEq(data.lockDurationAfterMigration, initBptLockDuration, "BPT lock duration mismatch");
        assertEq(data.bptPercentageToMigrate, initBptPercentageToMigrate, "Share to migrate mismatch");
        assertEq(data.migrationWeightProjectToken, initNewWeightProjectToken, "New weightProjectToken mismatch");
        assertEq(data.migrationWeightReserveToken, initNewWeightReserveToken, "New weightReserveToken mismatch");
        assertEq(vault.getPoolRoleAccounts(pool).poolCreator, bob, "Incorrect pool creator");
        //TODO rest of it
    }

    function testCreatePoolWithMigrationParamsButNoRouter() public {
        vm.expectRevert(BaseLBPFactory.InvalidMigrationRouter.selector);
        lbPoolFactory = deployFixedPriceLBPoolFactory(
            IVault(address(vault)),
            365 days,
            factoryVersion,
            poolVersion,
            address(router),
            address(0) // no migration router
        );

        LBPCommonParams memory lbpCommonParams = LBPCommonParams({
            name: "LBPool",
            symbol: "LBP",
            owner: bob,
            projectToken: projectToken,
            reserveToken: reserveToken,
            startTime: uint32(block.timestamp + DEFAULT_START_OFFSET),
            endTime: uint32(block.timestamp + DEFAULT_END_OFFSET),
            blockProjectTokenSwapsIn: DEFAULT_PROJECT_TOKENS_SWAP_IN
        });

        MigrationParams memory migrationParams = MigrationParams({
            lockDurationAfterMigration: 30 days,
            bptPercentageToMigrate: 50e16,
            migrationWeightProjectToken: 60e16,
            migrationWeightReserveToken: 40e16
        });

        FactoryParams memory factoryParams = FactoryParams({
            vault: vault,
            trustedRouter: address(router),
            migrationRouter: address(0), // no router
            poolVersion: poolVersion
        });

        vm.expectRevert(LBPValidation.MigrationRouterRequired.selector);
        new FixedPriceLBPool(lbpCommonParams, migrationParams, factoryParams, DEFAULT_RATE);
    }

    function testCreatePoolWithInvalidMigrationWeights() public {
        uint256 initBptLockDuration = 30 days;
        uint256 initBptPercentageToMigrate = 50e16; // 50%
        uint256 minReserveTokenWeight = 20e16; // 20%
        uint256 maxProjectTokenWeight = 100e16 - minReserveTokenWeight;

        vm.expectRevert(LBPValidation.InvalidMigrationWeights.selector);
        _createFixedPriceLBPoolWithMigration(address(0), initBptLockDuration, initBptPercentageToMigrate, 0, 100e16);

        vm.expectRevert(LBPValidation.InvalidMigrationWeights.selector);
        _createFixedPriceLBPoolWithMigration(address(0), initBptLockDuration, initBptPercentageToMigrate, 100e16, 0);

        vm.expectRevert(LBPValidation.InvalidMigrationWeights.selector);
        _createFixedPriceLBPoolWithMigration(
            address(0),
            initBptLockDuration,
            initBptPercentageToMigrate,
            maxProjectTokenWeight + 1,
            minReserveTokenWeight - 1
        );

        vm.expectRevert(LBPValidation.InvalidMigrationWeights.selector);
        _createFixedPriceLBPoolWithMigration(
            address(0),
            initBptLockDuration,
            initBptPercentageToMigrate,
            100e16,
            100e16
        );

        vm.expectRevert(LBPValidation.InvalidMigrationWeights.selector);
        _createFixedPriceLBPoolWithMigration(
            address(0),
            initBptLockDuration,
            initBptPercentageToMigrate,
            100e16,
            50e16
        );
    }

    function testCreatePoolWithInvalidBptPercentageToMigrateTooHigh() public {
        uint256 initBptLockDuration = 30 days;
        uint256 initNewWeightProjectToken = 60e16; // 60%
        uint256 initNewWeightReserveToken = 40e16; // 40%

        // BPT percentage to migrate cannot be zero
        vm.expectRevert(LBPValidation.InvalidBptPercentageToMigrate.selector);
        _createFixedPriceLBPoolWithMigration(
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
        vm.expectRevert(LBPValidation.InvalidBptPercentageToMigrate.selector);
        _createFixedPriceLBPoolWithMigration(
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

        vm.expectRevert(LBPValidation.InvalidBptLockDuration.selector);
        _createFixedPriceLBPoolWithMigration(
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

        vm.expectRevert(LBPValidation.InvalidBptLockDuration.selector);
        _createFixedPriceLBPoolWithMigration(
            address(0),
            0,
            initBptPercentageToMigrate,
            initNewWeightProjectToken,
            initNewWeightReserveToken
        );
    }

    function testAddLiquidityPermission() public {
        (pool, ) = _createFixedPriceLBPool(
            address(0),
            uint32(block.timestamp + 100),
            uint32(block.timestamp + 200),
            true
        );
        initPool();

        // Try to add to the pool without permission.
        vm.expectRevert(IVaultErrors.BeforeAddLiquidityHookFailed.selector);
        router.addLiquidityProportional(pool, [DEFAULT_AMOUNT, DEFAULT_AMOUNT].toMemoryArray(), 0, false, bytes(""));

        // The owner is allowed to add.
        vm.prank(bob);
        router.addLiquidityProportional(pool, [DEFAULT_AMOUNT, DEFAULT_AMOUNT].toMemoryArray(), 0, false, bytes(""));
    }

    function testDonationNotAllowed() public {
        (pool, ) = _createFixedPriceLBPool(
            address(0),
            uint32(block.timestamp + 100),
            uint32(block.timestamp + 200),
            true
        );
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

    function testRatesInFactory() public {
        LBPCommonParams memory lbpCommonParams = LBPCommonParams({
            name: "LBPool",
            symbol: "LBP",
            owner: bob,
            projectToken: projectToken,
            reserveToken: reserveToken,
            startTime: uint32(block.timestamp + DEFAULT_START_OFFSET),
            endTime: uint32(block.timestamp + DEFAULT_END_OFFSET),
            blockProjectTokenSwapsIn: DEFAULT_PROJECT_TOKENS_SWAP_IN
        });

        uint256 salt = _saltCounter++;

        vm.expectRevert(IFixedPriceLBPool.InvalidProjectTokenRate.selector);
        lbPoolFactory.create(lbpCommonParams, 0, swapFee, bytes32(salt), address(0));
    }

    function testBuyOnlyInFactory() public {
        LBPCommonParams memory lbpCommonParams = LBPCommonParams({
            name: "LBPool",
            symbol: "LBP",
            owner: bob,
            projectToken: projectToken,
            reserveToken: reserveToken,
            startTime: uint32(block.timestamp + DEFAULT_START_OFFSET),
            endTime: uint32(block.timestamp + DEFAULT_END_OFFSET),
            blockProjectTokenSwapsIn: false
        });

        uint256 salt = _saltCounter++;

        vm.expectRevert(IFixedPriceLBPool.TokenSwapsInUnsupported.selector);
        lbPoolFactory.create(lbpCommonParams, DEFAULT_RATE, swapFee, bytes32(salt), address(0));
    }

    function _createFixedPriceLBPoolWithMigration(
        address poolCreator,
        uint256 lockDurationAfterMigration,
        uint256 bptPercentageToMigrate,
        uint256 migrationWeightProjectToken,
        uint256 migrationWeightReserveToken
    ) internal returns (address newPool, bytes memory poolArgs) {
        LBPCommonParams memory lbpCommonParams = LBPCommonParams({
            name: "LBPool",
            symbol: "LBP",
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
            DEFAULT_RATE,
            swapFee,
            bytes32(salt),
            poolCreator_
        );

        poolArgs = abi.encode(lbpCommonParams, migrationParams, DEFAULT_RATE, factoryParams);

        return (newPool, poolArgs);
    }

    function _createFixedPriceLBPool(
        address poolCreator,
        uint32 startTime,
        uint32 endTime,
        bool blockProjectTokenSwapsIn
    ) internal returns (address newPool, bytes memory poolArgs) {
        LBPCommonParams memory lbpCommonParams = LBPCommonParams({
            name: "FixedPriceLBPool",
            symbol: "FLBP",
            owner: bob,
            projectToken: projectToken,
            reserveToken: reserveToken,
            startTime: startTime,
            endTime: endTime,
            blockProjectTokenSwapsIn: blockProjectTokenSwapsIn
        });

        MigrationParams memory migrationParams;

        FactoryParams memory factoryParams = FactoryParams({
            vault: vault,
            trustedRouter: address(router),
            migrationRouter: address(migrationRouter),
            poolVersion: poolVersion
        });

        uint256 salt = _saltCounter++;

        newPool = lbPoolFactory.create(lbpCommonParams, DEFAULT_RATE, swapFee, bytes32(salt), poolCreator);

        poolArgs = abi.encode(lbpCommonParams, migrationParams, factoryParams, DEFAULT_RATE);
    }
}
