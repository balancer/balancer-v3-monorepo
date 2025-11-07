// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Create2 } from "@openzeppelin/contracts/utils/Create2.sol";

import { ContractType } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IBalancerContractRegistry.sol";
import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { IWeightedPool } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/IWeightedPool.sol";
import { ISenderGuard } from "@balancer-labs/v3-interfaces/contracts/vault/ISenderGuard.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPCommon.sol";
import "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPool.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { BalancerContractRegistry } from "@balancer-labs/v3-standalone-utils/contracts/BalancerContractRegistry.sol";
import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { LBPMigrationRouter } from "../../contracts/lbp/LBPMigrationRouter.sol";
import { GradualValueChange } from "../../contracts/lib/GradualValueChange.sol";
import { BaseLBPFactory } from "../../contracts/lbp/BaseLBPFactory.sol";
import { LBPoolFactory } from "../../contracts/lbp/LBPoolFactory.sol";
import { LBPValidation } from "../../contracts/lbp/LBPValidation.sol";
import { LBPCommon } from "../../contracts/lbp/LBPCommon.sol";
import { WeightedLBPTest } from "./utils/WeightedLBPTest.sol";
import { LBPool } from "../../contracts/lbp/LBPool.sol";

contract LBPoolTest is WeightedLBPTest {
    using ArrayHelpers for *;
    using CastingHelpers for address[];
    using FixedPoint for uint256;

    function setUp() public virtual override {
        super.setUp();
    }

    function createPool() internal virtual override returns (address newPool, bytes memory poolArgs) {
        return
            _createLBPool(
                address(0), // Pool creator
                uint32(block.timestamp + DEFAULT_START_OFFSET),
                uint32(block.timestamp + DEFAULT_END_OFFSET),
                DEFAULT_PROJECT_TOKENS_SWAP_IN
            );
    }

    /********************************************************
                        Pool Constructor
    ********************************************************/

    function testCreatePoolWithInvalidTokens() public {
        LBPCommonParams memory lbpCommonParams = LBPCommonParams({
            name: "LBPool",
            symbol: "LBP",
            owner: bob,
            projectToken: IERC20(address(0)),
            reserveToken: reserveToken,
            startTime: block.timestamp,
            endTime: block.timestamp + 1000,
            blockProjectTokenSwapsIn: false
        });

        LBPParams memory lbpParams = LBPParams({
            projectTokenStartWeight: 90e16,
            reserveTokenStartWeight: 10e16,
            projectTokenEndWeight: 10e16,
            reserveTokenEndWeight: 90e16
        });

        vm.expectRevert(LBPValidation.InvalidProjectToken.selector);
        lbPoolFactory.create(lbpCommonParams, lbpParams, swapFee, ONE_BYTES32, address(0));

        lbpCommonParams.projectToken = projectToken;
        lbpCommonParams.reserveToken = IERC20(address(0));
        vm.expectRevert(LBPValidation.InvalidReserveToken.selector);
        lbPoolFactory.create(lbpCommonParams, lbpParams, swapFee, ONE_BYTES32, address(0));

        lbpCommonParams.reserveToken = projectToken;
        vm.expectRevert(LBPValidation.TokensMustBeDifferent.selector);
        lbPoolFactory.create(lbpCommonParams, lbpParams, swapFee, ONE_BYTES32, address(0));
    }

    function testCreatePoolLowProjectStartWeight() public {
        // Min weight is 1e16 (1%).
        uint256 wrongWeight = 0.5e16;

        vm.expectRevert(IWeightedPool.MinWeight.selector);
        _createLBPoolWithCustomWeights(
            address(0), // Pool creator
            wrongWeight,
            wrongWeight.complement(),
            endWeights[projectIdx],
            endWeights[reserveIdx],
            uint32(block.timestamp + DEFAULT_START_OFFSET),
            uint32(block.timestamp + DEFAULT_END_OFFSET),
            DEFAULT_PROJECT_TOKENS_SWAP_IN
        );
    }

    function testCreatePoolLowReserveStartWeight() public {
        // Min weight is 1e16 (1%).
        uint256 wrongWeight = 0.5e16;

        vm.expectRevert(IWeightedPool.MinWeight.selector);
        _createLBPoolWithCustomWeights(
            address(0), // Pool creator
            wrongWeight.complement(),
            wrongWeight,
            endWeights[projectIdx],
            endWeights[reserveIdx],
            uint32(block.timestamp + DEFAULT_START_OFFSET),
            uint32(block.timestamp + DEFAULT_END_OFFSET),
            DEFAULT_PROJECT_TOKENS_SWAP_IN
        );
    }

    function testCreatePoolLowProjectEndWeight() public {
        // Min weight is 1e16 (1%).
        uint256 wrongWeight = 0.5e16;

        vm.expectRevert(IWeightedPool.MinWeight.selector);
        _createLBPoolWithCustomWeights(
            address(0), // Pool creator
            startWeights[projectIdx],
            startWeights[reserveIdx],
            wrongWeight,
            wrongWeight.complement(),
            uint32(block.timestamp + DEFAULT_START_OFFSET),
            uint32(block.timestamp + DEFAULT_END_OFFSET),
            DEFAULT_PROJECT_TOKENS_SWAP_IN
        );
    }

    function testCreatePoolLowReserveEndWeight() public {
        // Min weight is 1e16 (1%).
        uint256 wrongWeight = 0.5e16;

        vm.expectRevert(IWeightedPool.MinWeight.selector);
        _createLBPoolWithCustomWeights(
            address(0), // Pool creator
            startWeights[projectIdx],
            startWeights[reserveIdx],
            wrongWeight.complement(),
            wrongWeight,
            uint32(block.timestamp + DEFAULT_START_OFFSET),
            uint32(block.timestamp + DEFAULT_END_OFFSET),
            DEFAULT_PROJECT_TOKENS_SWAP_IN
        );
    }

    function testCreatePoolNotNormalizedStartWeights() public {
        vm.expectRevert(IWeightedPool.NormalizedWeightInvariant.selector);
        _createLBPoolWithCustomWeights(
            address(0), // Pool creator
            startWeights[projectIdx],
            startWeights[reserveIdx] - 1,
            endWeights[projectIdx],
            endWeights[reserveIdx],
            uint32(block.timestamp + DEFAULT_START_OFFSET),
            uint32(block.timestamp + DEFAULT_END_OFFSET),
            DEFAULT_PROJECT_TOKENS_SWAP_IN
        );
    }

    function testCreatePoolNotNormalizedEndWeights() public {
        vm.expectRevert(IWeightedPool.NormalizedWeightInvariant.selector);
        _createLBPoolWithCustomWeights(
            address(0), // Pool creator
            startWeights[projectIdx],
            startWeights[reserveIdx],
            endWeights[projectIdx],
            endWeights[reserveIdx] - 1,
            uint32(block.timestamp + DEFAULT_START_OFFSET),
            uint32(block.timestamp + DEFAULT_END_OFFSET),
            DEFAULT_PROJECT_TOKENS_SWAP_IN
        );
    }

    function testCreatePoolTimeTravel() public {
        uint32 startTime = uint32(block.timestamp + 200);
        uint32 endTime = uint32(block.timestamp + 100);

        vm.expectRevert(abi.encodeWithSelector(GradualValueChange.InvalidStartTime.selector, startTime, endTime));
        _createLBPoolWithCustomWeights(
            address(0), // Pool creator
            startWeights[projectIdx],
            startWeights[reserveIdx],
            endWeights[projectIdx],
            endWeights[reserveIdx],
            startTime,
            endTime, // EndTime after StartTime, it should revert.
            DEFAULT_PROJECT_TOKENS_SWAP_IN
        );
    }

    function testCreatePoolTimeTravelWrongEndTime() public {
        uint32 startTime = uint32(block.timestamp + 200);
        uint32 endTime = startTime - 1;

        vm.expectRevert(abi.encodeWithSelector(GradualValueChange.InvalidStartTime.selector, startTime, endTime));
        _createLBPoolWithCustomWeights(
            address(0), // Pool creator
            startWeights[projectIdx],
            startWeights[reserveIdx],
            endWeights[projectIdx],
            endWeights[reserveIdx],
            startTime,
            endTime, // EndTime = StartTime, it should revert.
            DEFAULT_PROJECT_TOKENS_SWAP_IN
        );
    }

    function testCreatePoolStartTimeInPast() public {
        // Set startTime in the past
        uint32 pastStartTime = uint32(block.timestamp - 100);
        uint32 endTime = uint32(block.timestamp + DEFAULT_END_OFFSET);

        vm.expectEmit();
        // The event should be emitted with block.timestamp as startTime, not the past time
        emit LBPool.GradualWeightUpdateScheduled(block.timestamp, endTime, startWeights, endWeights);

        _createLBPoolWithCustomWeights(
            address(0), // Pool creator
            startWeights[projectIdx],
            startWeights[reserveIdx],
            endWeights[projectIdx],
            endWeights[reserveIdx],
            pastStartTime,
            endTime,
            DEFAULT_PROJECT_TOKENS_SWAP_IN
        );
    }

    function testCreatePoolEvents() public {
        uint32 startTime = uint32(block.timestamp + DEFAULT_START_OFFSET);
        uint32 endTime = uint32(block.timestamp + DEFAULT_END_OFFSET);

        uint256 preCreateSnapshotId = vm.snapshotState();

        vm.expectEmit();
        emit LBPool.GradualWeightUpdateScheduled(startTime, endTime, startWeights, endWeights);

        (address newPool, ) = _createLBPoolWithCustomWeights(
            address(0), // Pool creator
            startWeights[projectIdx],
            startWeights[reserveIdx],
            endWeights[projectIdx],
            endWeights[reserveIdx],
            startTime,
            endTime,
            DEFAULT_PROJECT_TOKENS_SWAP_IN
        );

        vm.revertToState(preCreateSnapshotId);

        vm.expectEmit();
        emit BaseLBPFactory.LBPoolCreated(newPool, projectToken, reserveToken);

        vm.expectEmit();
        emit LBPoolFactory.WeightedLBPoolCreated(bob, DEFAULT_PROJECT_TOKENS_SWAP_IN, false); // no migration

        // Should create the same pool address again.
        _createLBPoolWithCustomWeights(
            address(0), // Pool creator
            startWeights[projectIdx],
            startWeights[reserveIdx],
            endWeights[projectIdx],
            endWeights[reserveIdx],
            startTime,
            endTime,
            DEFAULT_PROJECT_TOKENS_SWAP_IN
        );
    }

    /********************************************************
                            Getters
    ********************************************************/

    function testGetTrustedRouter() public view {
        assertEq(ILBPCommon(pool).getTrustedRouter(), address(router), "Wrong trusted router");
    }

    function testGetMigrationParams() public view {
        LBPoolImmutableData memory data = ILBPool(pool).getLBPoolImmutableData();

        assertEq(data.migrationRouter, ZERO_ADDRESS, "Migration router should be zero address");
        assertEq(data.lockDurationAfterMigration, 0, "BPT lock duration should be zero");
        assertEq(data.bptPercentageToMigrate, 0, "Share to migrate should be zero");
        assertEq(data.migrationWeightProjectToken, 0, "Migration weight of project token should be zero");
        assertEq(data.migrationWeightReserveToken, 0, "Migration weight of reserve token should be zero");
    }

    function testGetMigrationParamsWithMigration() public {
        uint256 initBptLockDuration = 30 days;
        uint256 initBptPercentageToMigrate = 50e16; // 50%
        uint256 initNewWeightProjectToken = 60e16; // 60%
        uint256 initNewWeightReserveToken = 40e16; // 40%

        (pool, ) = _createLBPoolWithMigration(
            address(0), // Pool creator
            initBptLockDuration,
            initBptPercentageToMigrate,
            initNewWeightProjectToken,
            initNewWeightReserveToken
        );
        initPool();

        LBPoolImmutableData memory data = ILBPool(pool).getLBPoolImmutableData();

        assertEq(data.migrationRouter, address(migrationRouter), "Migration router mismatch");
        assertEq(data.lockDurationAfterMigration, initBptLockDuration, "BPT lock duration mismatch");
        assertEq(data.bptPercentageToMigrate, initBptPercentageToMigrate, "Share to migrate mismatch");
        assertEq(data.migrationWeightProjectToken, initNewWeightProjectToken, "New project token weight mismatch");
        assertEq(data.migrationWeightReserveToken, initNewWeightReserveToken, "New reserve token weight mismatch");

        MigrationParams memory migrationParams = ILBPCommon(pool).getMigrationParameters();
        assertEq(
            migrationParams.lockDurationAfterMigration,
            initBptLockDuration,
            "BPT lock duration mismatch (params)"
        );
        assertEq(
            migrationParams.bptPercentageToMigrate,
            initBptPercentageToMigrate,
            "Share to migrate mismatch (params)"
        );
        assertEq(
            migrationParams.migrationWeightProjectToken,
            initNewWeightProjectToken,
            "New project token weight mismatch (params)"
        );
        assertEq(
            migrationParams.migrationWeightReserveToken,
            initNewWeightReserveToken,
            "New reserve token weight mismatch (params)"
        );
    }

    function testGetProjectToken() public view {
        assertEq(address(ILBPCommon(pool).getProjectToken()), address(projectToken), "Wrong project token");
    }

    function testGetReserveToken() public view {
        assertEq(address(ILBPCommon(pool).getReserveToken()), address(reserveToken), "Wrong reserve token");
    }

    function testGetProjectIndices() public view {
        (uint256 expectedProjectTokenIndex, uint256 expectedReserveTokenIndex) = projectToken < reserveToken
            ? (0, 1)
            : (1, 0);

        (uint256 projectTokenIndex, uint256 reserveTokenIndex) = ILBPCommon(pool).getTokenIndices();

        assertEq(projectTokenIndex, expectedProjectTokenIndex, "Wrong project token index");
        assertEq(reserveTokenIndex, expectedReserveTokenIndex, "Wrong reserve token index");
    }

    function testGradualWeightUpdateParams() public {
        uint32 customStartTime = uint32(block.timestamp + 1);
        uint32 customEndTime = uint32(block.timestamp + 300);
        uint256[] memory customStartWeights = [uint256(22e16), uint256(78e16)].toMemoryArray();
        uint256[] memory customEndWeights = [uint256(65e16), uint256(35e16)].toMemoryArray();

        (address newPool, ) = _createLBPoolWithCustomWeights(
            address(0), // Pool creator
            customStartWeights[projectIdx],
            customStartWeights[reserveIdx],
            customEndWeights[projectIdx],
            customEndWeights[reserveIdx],
            customStartTime,
            customEndTime,
            DEFAULT_PROJECT_TOKENS_SWAP_IN
        );

        (
            uint256 poolStartTime,
            uint256 poolEndTime,
            uint256[] memory poolStartWeights,
            uint256[] memory poolEndWeights
        ) = ILBPool(newPool).getGradualWeightUpdateParams();
        assertEq(poolStartTime, customStartTime, "Start time mismatch");
        assertEq(poolEndTime, customEndTime, "End time mismatch");

        assertEq(poolStartWeights.length, customStartWeights.length, "Start Weights length mismatch");
        assertEq(poolStartWeights[projectIdx], customStartWeights[projectIdx], "Project Start Weight mismatch");
        assertEq(poolStartWeights[reserveIdx], customStartWeights[reserveIdx], "Reserve Start Weight mismatch");

        assertEq(poolEndWeights.length, customEndWeights.length, "End Weights length mismatch");
        assertEq(poolEndWeights[projectIdx], customEndWeights[projectIdx], "Project End Weight mismatch");
        assertEq(poolEndWeights[reserveIdx], customEndWeights[reserveIdx], "Reserve End Weight mismatch");
    }

    function testIsSwapEnabled() public {
        uint32 startTime = uint32(block.timestamp + DEFAULT_START_OFFSET);
        uint32 endTime = uint32(block.timestamp + DEFAULT_END_OFFSET);

        assertFalse(ILBPCommon(pool).isSwapEnabled(), "Swap should be disabled before start time");

        vm.warp(startTime + 1);
        assertTrue(ILBPCommon(pool).isSwapEnabled(), "Swap should be enabled after start time");

        vm.warp(endTime + 1);
        assertFalse(ILBPCommon(pool).isSwapEnabled(), "Swap should be disabled after end time");
    }

    function testIsProjectTokenSwapInBlocked() public {
        (address newPoolSwapDisabled, ) = _createLBPoolWithCustomWeights(
            address(0), // Pool creator
            startWeights[projectIdx],
            startWeights[reserveIdx],
            endWeights[projectIdx],
            endWeights[reserveIdx],
            uint32(block.timestamp + DEFAULT_START_OFFSET),
            uint32(block.timestamp + DEFAULT_END_OFFSET),
            false
        );

        assertFalse(
            ILBPCommon(newPoolSwapDisabled).isProjectTokenSwapInBlocked(),
            "Swap of Project Token in is blocked"
        );

        (address newPoolSwapEnabled, ) = _createLBPoolWithCustomWeights(
            address(0), // Pool creator
            startWeights[projectIdx],
            startWeights[reserveIdx],
            endWeights[projectIdx],
            endWeights[reserveIdx],
            uint32(block.timestamp + DEFAULT_START_OFFSET),
            uint32(block.timestamp + DEFAULT_END_OFFSET),
            true
        );

        assertTrue(
            ILBPCommon(newPoolSwapEnabled).isProjectTokenSwapInBlocked(),
            "Swap of Project Token in is not blocked"
        );
    }

    function testGetWeightedPoolDynamicData() public {
        // This function is not implemented, since the weights are not immutable. So, it should revert.
        vm.expectRevert(LBPool.NotImplemented.selector);
        IWeightedPool(pool).getWeightedPoolDynamicData();
    }

    function testGetWeightedPoolImmutableData() public {
        // This function is not implemented, since the weights are not immutable. So, it should revert.
        vm.expectRevert(LBPool.NotImplemented.selector);
        IWeightedPool(pool).getWeightedPoolImmutableData();
    }

    function testGetLBPoolDynamicData() public view {
        LBPoolDynamicData memory data = ILBPool(pool).getLBPoolDynamicData();

        uint256[] memory balancesLiveScaled18 = vault.getCurrentLiveBalances(pool);
        assertEq(data.balancesLiveScaled18.length, balancesLiveScaled18.length, "balancesLiveScaled18 length mismatch");
        assertEq(
            data.balancesLiveScaled18[projectIdx],
            balancesLiveScaled18[projectIdx],
            "Project token's balancesLiveScaled18 mismatch"
        );
        assertEq(
            data.balancesLiveScaled18[reserveIdx],
            balancesLiveScaled18[reserveIdx],
            "Reserve token's balancesLiveScaled18 mismatch"
        );

        assertEq(
            data.staticSwapFeePercentage,
            vault.getStaticSwapFeePercentage(pool),
            "staticSwapFeePercentage mismatch"
        );
        assertEq(data.totalSupply, IERC20(pool).totalSupply(), "TotalSupply mismatch");

        PoolConfig memory poolConfig = vault.getPoolConfig(pool);
        assertEq(data.isPoolInitialized, poolConfig.isPoolInitialized, "isPoolInitialized mismatch");
        assertEq(data.isPoolPaused, poolConfig.isPoolPaused, "isPoolInitialized mismatch");
        assertEq(data.isPoolInRecoveryMode, poolConfig.isPoolInRecoveryMode, "isPoolInitialized mismatch");

        assertEq(data.isSwapEnabled, ILBPCommon(pool).isSwapEnabled(), "isSwapEnabled mismatch");

        assertEq(data.normalizedWeights.length, startWeights.length, "normalizedWeights length mismatch");
        assertEq(data.normalizedWeights[projectIdx], startWeights[projectIdx], "project weight mismatch");
        assertEq(data.normalizedWeights[reserveIdx], startWeights[reserveIdx], "reserve weight mismatch");
    }

    function testGetLBPoolDynamicDataWeightInterpolation() public {
        // Check initial weights
        LBPoolDynamicData memory initialData = ILBPool(pool).getLBPoolDynamicData();
        assertEq(
            initialData.normalizedWeights[projectIdx],
            startWeights[projectIdx],
            "Initial project weight mismatch"
        );
        assertEq(
            initialData.normalizedWeights[reserveIdx],
            startWeights[reserveIdx],
            "Initial reserve weight mismatch"
        );

        // Warp to middle of weight update period
        vm.warp(block.timestamp + DEFAULT_START_OFFSET + 50);

        // Check interpolated weights
        LBPoolDynamicData memory midData = ILBPool(pool).getLBPoolDynamicData();

        // Calculate expected weights (average between start and end weights)
        uint256 expectedProjectWeight = (startWeights[projectIdx] + endWeights[projectIdx]) / 2;
        uint256 expectedReserveWeight = (startWeights[reserveIdx] + endWeights[reserveIdx]) / 2;

        // Allow for small rounding differences
        assertEq(midData.normalizedWeights[projectIdx], expectedProjectWeight, "Interpolated project weight mismatch");
        assertEq(midData.normalizedWeights[reserveIdx], expectedReserveWeight, "Interpolated reserve weight mismatch");

        // Warp to end of weight update period
        vm.warp(block.timestamp + DEFAULT_END_OFFSET);

        // Check final weights
        LBPoolDynamicData memory finalData = ILBPool(pool).getLBPoolDynamicData();
        assertEq(finalData.normalizedWeights[projectIdx], endWeights[projectIdx], "Final project weight mismatch");
        assertEq(finalData.normalizedWeights[reserveIdx], endWeights[reserveIdx], "Final reserve weight mismatch");
    }

    function testGetLBPoolImmutableData() public view {
        LBPoolImmutableData memory data = ILBPool(pool).getLBPoolImmutableData();

        // Check tokens array matches pool tokens
        IERC20[] memory poolTokens = vault.getPoolTokens(pool);
        assertEq(data.tokens.length, poolTokens.length, "tokens length mismatch");
        assertEq(address(data.tokens[projectIdx]), address(poolTokens[projectIdx]), "Project token mismatch");
        assertEq(address(data.tokens[reserveIdx]), address(poolTokens[reserveIdx]), "Reserve token mismatch");
        assertEq(data.projectTokenIndex, projectIdx, "Project token index mismatch");
        assertEq(data.reserveTokenIndex, reserveIdx, "Reserve token index mismatch");

        // Check decimal scaling factors
        (uint256[] memory decimalScalingFactors, ) = vault.getPoolTokenRates(pool);
        assertEq(
            data.decimalScalingFactors.length,
            decimalScalingFactors.length,
            "decimalScalingFactors length mismatch"
        );
        assertEq(
            data.decimalScalingFactors[projectIdx],
            decimalScalingFactors[projectIdx],
            "Project scaling factor mismatch"
        );
        assertEq(
            data.decimalScalingFactors[reserveIdx],
            decimalScalingFactors[reserveIdx],
            "Reserve scaling factor mismatch"
        );

        // Check project token swap in setting
        assertEq(
            data.isProjectTokenSwapInBlocked,
            DEFAULT_PROJECT_TOKENS_SWAP_IN,
            "Project token swap in setting mismatch"
        );

        // Check start and end times
        assertEq(data.startTime, block.timestamp + DEFAULT_START_OFFSET, "Start time mismatch");
        assertEq(data.endTime, block.timestamp + DEFAULT_END_OFFSET, "End time mismatch");

        // Check start weights
        assertEq(data.startWeights.length, startWeights.length, "Start weights length mismatch");
        assertEq(data.startWeights[projectIdx], startWeights[projectIdx], "Project start weight mismatch");
        assertEq(data.startWeights[reserveIdx], startWeights[reserveIdx], "Reserve start weight mismatch");

        // Check end weights
        assertEq(data.endWeights.length, endWeights.length, "End weights length mismatch");
        assertEq(data.endWeights[projectIdx], endWeights[projectIdx], "Project end weight mismatch");
        assertEq(data.endWeights[reserveIdx], endWeights[reserveIdx], "Reserve end weight mismatch");
    }

    /*******************************************************************************
                                    Base Pool Hooks
    *******************************************************************************/

    function testOnSwapDisabled() public {
        // Create swap request params
        PoolSwapParams memory request = PoolSwapParams({
            kind: SwapKind.EXACT_IN,
            amountGivenScaled18: 1e18,
            balancesScaled18: vault.getCurrentLiveBalances(pool),
            indexIn: reserveIdx,
            indexOut: projectIdx,
            router: address(router),
            userData: bytes("")
        });

        // Before start time, swaps should be disabled
        vm.expectRevert(LBPCommon.SwapsDisabled.selector);
        vm.prank(address(vault));
        IBasePool(pool).onSwap(request);

        // Warp to after end time
        vm.warp(block.timestamp + DEFAULT_END_OFFSET + 1);

        // After end time, swaps should also be disabled
        vm.expectRevert(LBPCommon.SwapsDisabled.selector);
        vm.prank(address(vault));
        IBasePool(pool).onSwap(request);
    }

    function testOnSwapProjectTokenInNotAllowed() public {
        // Warp to when swaps are enabled
        vm.warp(block.timestamp + DEFAULT_START_OFFSET + 1);

        // Create swap request params - trying to swap project token for reserve token
        PoolSwapParams memory request = PoolSwapParams({
            kind: SwapKind.EXACT_IN,
            amountGivenScaled18: 1e18,
            balancesScaled18: vault.getCurrentLiveBalances(pool),
            indexIn: projectIdx, // Project token as input
            indexOut: reserveIdx, // Reserve token as output
            router: address(router),
            userData: bytes("")
        });

        // Should revert when trying to swap project token in
        vm.expectRevert(LBPCommon.SwapOfProjectTokenIn.selector);
        vm.prank(address(vault));
        IBasePool(pool).onSwap(request);
    }

    function testOnSwapProjectTokenInAllowed() public {
        // Deploy a new pool with project token swaps enabled
        (pool, ) = _createLBPoolWithCustomWeights(
            address(0), // Pool creator
            startWeights[projectIdx],
            startWeights[reserveIdx],
            endWeights[projectIdx],
            endWeights[reserveIdx],
            uint32(block.timestamp + DEFAULT_START_OFFSET),
            uint32(block.timestamp + DEFAULT_END_OFFSET),
            false // Do not block project token swaps in
        );
        initPool();

        // Warp to when swaps are enabled
        vm.warp(block.timestamp + DEFAULT_START_OFFSET + 1);

        // Create swap request params - swapping project token for reserve token
        PoolSwapParams memory request = PoolSwapParams({
            kind: SwapKind.EXACT_IN,
            amountGivenScaled18: 1e18,
            balancesScaled18: vault.getCurrentLiveBalances(pool),
            indexIn: projectIdx,
            indexOut: reserveIdx,
            router: address(router),
            userData: bytes("")
        });

        // Mock vault call to onSwap
        vm.prank(address(vault));
        uint256 amountCalculated = IBasePool(pool).onSwap(request);

        // Verify amount calculated is non-zero
        assertGt(amountCalculated, 0, "Swap amount should be greater than zero");
    }

    function testOnSwap() public {
        // Warp to when swaps are enabled
        vm.warp(block.timestamp + DEFAULT_START_OFFSET + 1);

        // Create swap request params - swapping reserve token for project token
        PoolSwapParams memory request = PoolSwapParams({
            kind: SwapKind.EXACT_IN,
            amountGivenScaled18: 1e18,
            balancesScaled18: vault.getCurrentLiveBalances(pool),
            indexIn: reserveIdx,
            indexOut: projectIdx,
            router: address(router),
            userData: bytes("")
        });

        // Mock vault call to onSwap
        vm.prank(address(vault));
        uint256 amountCalculated = IBasePool(pool).onSwap(request);

        // Verify amount calculated is non-zero
        assertGt(amountCalculated, 0, "Swap amount should be greater than zero");
    }

    /*******************************************************************************
                                      Pool Hooks
    *******************************************************************************/

    function testOnRegisterMoreThanTwoTokens() public {
        // Create token config array with 3 tokens
        TokenConfig[] memory tokenConfig = vault.buildTokenConfig(
            [address(dai), address(usdc), address(wsteth)].toMemoryArray().asIERC20()
        );

        // Mock vault call to onRegister
        vm.prank(address(vault));
        vm.expectRevert(InputHelpers.InputLengthMismatch.selector);
        IHooks(pool).onRegister(
            poolFactory,
            pool,
            tokenConfig,
            LiquidityManagement({
                disableUnbalancedLiquidity: false,
                enableAddLiquidityCustom: false,
                enableRemoveLiquidityCustom: false,
                enableDonation: false
            })
        );
    }

    function testOnRegisterNonStandardToken() public {
        // Create token config array with one STANDARD and one WITH_RATE token
        TokenConfig[] memory tokenConfig = vault.buildTokenConfig(
            [address(dai), address(usdc)].toMemoryArray().asIERC20()
        );
        tokenConfig[1].tokenType = TokenType.WITH_RATE;

        // Mock vault call to onRegister
        vm.prank(address(vault));
        vm.expectRevert(IVaultErrors.InvalidTokenConfiguration.selector);
        IHooks(pool).onRegister(
            poolFactory,
            pool,
            tokenConfig,
            LiquidityManagement({
                disableUnbalancedLiquidity: false,
                enableAddLiquidityCustom: false,
                enableRemoveLiquidityCustom: false,
                enableDonation: false
            })
        );
    }

    function testOnRegisterWrongPool() public {
        TokenConfig[] memory tokenConfig = vault.buildTokenConfig(
            [address(dai), address(usdc)].toMemoryArray().asIERC20()
        );

        // Mock vault call to onRegister with wrong pool address
        vm.prank(address(vault));
        bool success = IHooks(pool).onRegister(
            poolFactory,
            address(1), // Wrong pool address
            tokenConfig,
            LiquidityManagement({
                disableUnbalancedLiquidity: false,
                enableAddLiquidityCustom: false,
                enableRemoveLiquidityCustom: false,
                enableDonation: false
            })
        );

        assertFalse(success, "onRegister should return false when pool address doesn't match");
    }

    function testOnRegisterSuccess() public {
        // Create token config array with 2 standard tokens
        TokenConfig[] memory tokenConfig = vault.buildTokenConfig(
            [address(dai), address(usdc)].toMemoryArray().asIERC20()
        );

        // Mock vault call to onRegister with correct parameters
        vm.prank(address(vault));
        bool success = IHooks(pool).onRegister(
            poolFactory, // Correct factory address
            pool, // Correct pool address
            tokenConfig,
            LiquidityManagement({
                disableUnbalancedLiquidity: false,
                enableAddLiquidityCustom: false,
                enableRemoveLiquidityCustom: false,
                enableDonation: false
            })
        );

        assertTrue(success, "onRegister should return true when parameters are valid");
    }

    function testGetHookFlags() public view {
        HookFlags memory flags = IHooks(pool).getHookFlags();

        // These should be true
        assertTrue(flags.shouldCallBeforeInitialize, "shouldCallBeforeInitialize should be true");
        assertTrue(flags.shouldCallBeforeAddLiquidity, "shouldCallBeforeAddLiquidity should be true");
        assertTrue(flags.shouldCallBeforeRemoveLiquidity, "shouldCallBeforeRemoveLiquidity should be true");

        // These should be false
        assertFalse(flags.enableHookAdjustedAmounts, "enableHookAdjustedAmounts should be false");
        assertFalse(flags.shouldCallAfterInitialize, "shouldCallAfterInitialize should be false");
        assertFalse(flags.shouldCallComputeDynamicSwapFee, "shouldCallComputeDynamicSwapFee should be false");
        assertFalse(flags.shouldCallBeforeSwap, "shouldCallBeforeSwap should be false");
        assertFalse(flags.shouldCallAfterSwap, "shouldCallAfterSwap should be false");
        assertFalse(flags.shouldCallAfterAddLiquidity, "shouldCallAfterAddLiquidity should be false");
        assertFalse(flags.shouldCallAfterRemoveLiquidity, "shouldCallAfterRemoveLiquidity should be false");
    }

    function testOnBeforeInitializeAfterStartTime() public {
        vm.warp(block.timestamp + DEFAULT_START_OFFSET + 1);

        vm.prank(address(vault));
        vm.expectRevert(LBPCommon.AddingLiquidityNotAllowed.selector);
        IHooks(pool).onBeforeInitialize(new uint256[](0), "");
    }

    function testOnBeforeInitializeWrongSender() public {
        // Warp to before start time (initialization is allowed before start time)
        vm.warp(block.timestamp + DEFAULT_START_OFFSET - 1);

        vm.prank(address(vault));
        // Mock router to return wrong factory address as sender
        _mockGetSender(address(1));

        assertFalse(
            IHooks(pool).onBeforeInitialize(new uint256[](0), ""),
            "onBeforeInitialize should return false when sender is not factory"
        );
    }

    function testOnBeforeInitialize() public {
        // Warp to before start time (initialization is allowed before start time)
        vm.warp(block.timestamp + DEFAULT_START_OFFSET - 1);

        vm.prank(address(vault));
        _mockGetSender(bob);

        assertTrue(
            IHooks(pool).onBeforeInitialize(new uint256[](0), ""),
            "onBeforeInitialize should return true with correct sender and before startTime"
        );
    }

    function testOnBeforeRemoveLiquidityBeforeEndTime() public {
        // Try to remove liquidity before end time.
        vm.prank(address(vault));
        vm.expectRevert(LBPCommon.RemovingLiquidityNotAllowed.selector);
        IHooks(pool).onBeforeRemoveLiquidity(
            ZERO_ADDRESS,
            ZERO_ADDRESS,
            RemoveLiquidityKind.PROPORTIONAL,
            0,
            new uint256[](0),
            new uint256[](0),
            bytes("")
        );
    }

    function testOnBeforeRemoveLiquidityAfterEndTime() public {
        // Warp to after end time, where removing liquidity is allowed.
        vm.warp(block.timestamp + DEFAULT_END_OFFSET + 1);

        vm.prank(address(vault));
        bool success = IHooks(pool).onBeforeRemoveLiquidity(
            ZERO_ADDRESS,
            ZERO_ADDRESS,
            RemoveLiquidityKind.PROPORTIONAL,
            0,
            new uint256[](0),
            new uint256[](0),
            bytes("")
        );

        assertTrue(success, "onBeforeRemoveLiquidity should return true after end time");
    }

    function testAddingLiquidityNotOwner() public {
        // Try to add liquidity to the pool.
        vm.expectRevert(IVaultErrors.BeforeAddLiquidityHookFailed.selector);
        router.addLiquidityProportional(pool, [poolInitAmount, poolInitAmount].toMemoryArray(), 1e18, false, bytes(""));
    }

    function testAddingLiquidityOwnerAfterStartTime() public {
        // Warp to after start time, where adding liquidity is forbidden.
        vm.warp(block.timestamp + DEFAULT_START_OFFSET + 1);

        // Try to add liquidity to the pool.
        vm.prank(bob);
        vm.expectRevert(LBPCommon.AddingLiquidityNotAllowed.selector);
        router.addLiquidityProportional(pool, [poolInitAmount, poolInitAmount].toMemoryArray(), 1e18, false, bytes(""));
    }

    function testAddingLiquidityOwnerBeforeStartTime() public {
        // Warp to before start time, where adding liquidity is allowed.
        vm.warp(block.timestamp + DEFAULT_START_OFFSET - 1);

        // Try to add liquidity to the pool.
        vm.prank(bob);
        router.addLiquidityProportional(pool, [poolInitAmount, poolInitAmount].toMemoryArray(), 1e18, false, bytes(""));
    }

    function testDonationOwnerNotAllowed() public {
        // Try to donate to the pool.
        vm.prank(bob);
        vm.expectRevert(IVaultErrors.DoesNotSupportDonation.selector);
        router.donate(pool, [poolInitAmount, poolInitAmount].toMemoryArray(), false, bytes(""));
    }

    function testOnBeforeRemoveLiquidity() public {
        // Warp to after end time, where removing liquidity is allowed.
        vm.warp(block.timestamp + DEFAULT_END_OFFSET + 1);

        vm.prank(address(vault));
        bool success = IHooks(pool).onBeforeRemoveLiquidity(
            address(router),
            ZERO_ADDRESS,
            RemoveLiquidityKind.PROPORTIONAL,
            0,
            new uint256[](0),
            new uint256[](0),
            bytes("")
        );

        assertTrue(success, "onBeforeRemoveLiquidity should return true after end time");
    }

    function testOnBeforeRemoveLiquidityWithMigrationRouter() public {
        (pool, ) = _createLBPoolWithMigration(
            address(0), // Pool creator
            30 days, // BPT lock duration
            50e16, // Share to migrate (50%)
            60e16, // New weight for project token (60%)
            40e16 // New weight for reserve token (40%)
        );
        initPool();

        assertEq(ILBPCommon(pool).getMigrationRouter(), address(migrationRouter), "Wrong migration router");

        // Warp to after end time, where removing liquidity is allowed.
        vm.warp(block.timestamp + DEFAULT_END_OFFSET + 1);

        vm.prank(address(vault));
        bool success = IHooks(pool).onBeforeRemoveLiquidity(
            address(migrationRouter),
            ZERO_ADDRESS,
            RemoveLiquidityKind.PROPORTIONAL,
            0,
            new uint256[](0),
            new uint256[](0),
            bytes("")
        );

        assertTrue(success, "onBeforeRemoveLiquidity should return true with migration router");
    }

    function testOnBeforeRemoveLiquidityWithMigrationRevertWithWrongRouter() public {
        (pool, ) = _createLBPoolWithMigration(
            address(0), // Pool creator
            30 days, // BPT lock duration
            50e16, // Share to migrate (50%)
            60e16, // New weight for project token (60%)
            40e16 // New weight for reserve token (40%)
        );
        initPool();

        // Warp to after end time, where removing liquidity is allowed.
        vm.warp(block.timestamp + DEFAULT_END_OFFSET + 1);

        vm.prank(address(vault));
        bool success = IHooks(pool).onBeforeRemoveLiquidity(
            address(router),
            ZERO_ADDRESS,
            RemoveLiquidityKind.PROPORTIONAL,
            0,
            new uint256[](0),
            new uint256[](0),
            bytes("")
        );

        assertFalse(success, "onBeforeRemoveLiquidity should return false with wrong migration router");
    }

    /*******************************************************************************
                                   Private Helpers
    *******************************************************************************/

    function _mockGetSender(address sender) private {
        vm.mockCall(address(router), abi.encodeWithSelector(ISenderGuard.getSender.selector), abi.encode(sender));
    }
}
