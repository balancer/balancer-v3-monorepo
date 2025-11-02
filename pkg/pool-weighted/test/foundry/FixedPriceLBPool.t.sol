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
import "@balancer-labs/v3-interfaces/contracts/pool-weighted/IFixedPriceLBPool.sol";
import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPCommon.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { BalancerContractRegistry } from "@balancer-labs/v3-standalone-utils/contracts/BalancerContractRegistry.sol";
import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { FixedPriceLBPoolContractsDeployer } from "./utils/FixedPriceLBPoolContractsDeployer.sol";
import { FixedPriceLBPoolFactory } from "../../contracts/lbp/FixedPriceLBPoolFactory.sol";
import { LBPMigrationRouter } from "../../contracts/lbp/LBPMigrationRouter.sol";
import { GradualValueChange } from "../../contracts/lib/GradualValueChange.sol";
import { FixedPriceLBPool } from "../../contracts/lbp/FixedPriceLBPool.sol";
import { BaseLBPFactory } from "../../contracts/lbp/BaseLBPFactory.sol";
import { LBPCommon } from "../../contracts/lbp/LBPCommon.sol";
import { BaseLBPTest } from "./utils/BaseLBPTest.sol";

contract FixedPriceLBPoolTest is BaseLBPTest, FixedPriceLBPoolContractsDeployer {
    using ArrayHelpers for *;
    using CastingHelpers for address[];
    using FixedPoint for uint256;

    uint256 internal constant DEFAULT_RATE = FixedPoint.ONE;

    FixedPriceLBPoolFactory internal lbPoolFactory;

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
        return
            _createFixedPriceLBPool(
                address(0), // Pool creator
                uint32(block.timestamp + DEFAULT_START_OFFSET),
                uint32(block.timestamp + DEFAULT_END_OFFSET),
                DEFAULT_PROJECT_TOKENS_SWAP_IN
            );
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
    
    /********************************************************
                        Pool Constructor
    ********************************************************/

    function testCreatePoolTimeTravel() public {
        uint32 startTime = uint32(block.timestamp + 200);
        uint32 endTime = uint32(block.timestamp + 100);

        vm.expectRevert(abi.encodeWithSelector(GradualValueChange.InvalidStartTime.selector, startTime, endTime));
        _createFixedPriceLBPool(
            address(0), // Pool creator
            startTime,
            endTime, // EndTime after StartTime, it should revert.
            DEFAULT_PROJECT_TOKENS_SWAP_IN
        );
    }

    function testCreatePoolTimeTravelWrongEndTime() public {
        uint32 startTime = uint32(block.timestamp + 200);
        uint32 endTime = startTime - 1;

        vm.expectRevert(abi.encodeWithSelector(GradualValueChange.InvalidStartTime.selector, startTime, endTime));
        _createFixedPriceLBPool(
            address(0), // Pool creator
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
        // The event should be emitted with block.timestamp as startTime, not the past time.
        emit FixedPriceLBPool.FixedPriceLBPoolCreated(bob, block.timestamp, endTime, DEFAULT_RATE, DEFAULT_PROJECT_TOKENS_SWAP_IN, false);

        _createFixedPriceLBPool(
            address(0), // Pool creator
            pastStartTime,
            endTime,
            DEFAULT_PROJECT_TOKENS_SWAP_IN
        );
    }

    function testCreatePoolEvents() public {
        uint32 startTime = uint32(block.timestamp + DEFAULT_START_OFFSET);
        uint32 endTime = uint32(block.timestamp + DEFAULT_END_OFFSET);

        vm.expectEmit();
        emit FixedPriceLBPool.FixedPriceLBPoolCreated(bob, startTime, endTime, DEFAULT_RATE, DEFAULT_PROJECT_TOKENS_SWAP_IN, false); // no migration

        vm.expectEmit();
        emit BaseLBPFactory.LBPoolCreated(pool, projectToken, reserveToken);

        _createFixedPriceLBPool(
            address(0), // Pool creator
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
        FixedPriceLBPoolImmutableData memory data = IFixedPriceLBPool(pool).getFixedPriceLBPoolImmutableData();

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

        FixedPriceLBPoolImmutableData memory data = IFixedPriceLBPool(pool).getFixedPriceLBPoolImmutableData();

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
        (address newPoolSwapDisabled, ) = _createFixedPriceLBPool(
            address(0), // Pool creator
            uint32(block.timestamp + DEFAULT_START_OFFSET),
            uint32(block.timestamp + DEFAULT_END_OFFSET),
            false
        );

        assertFalse(ILBPCommon(newPoolSwapDisabled).isProjectTokenSwapInBlocked(), "Swap of Project Token in is blocked");

        (address newPoolSwapEnabled, ) = _createFixedPriceLBPool(
            address(0), // Pool creator
            uint32(block.timestamp + DEFAULT_START_OFFSET),
            uint32(block.timestamp + DEFAULT_END_OFFSET),
            true
        );

        assertTrue(ILBPCommon(newPoolSwapEnabled).isProjectTokenSwapInBlocked(), "Swap of Project Token in is not blocked");
    }

    function testGetFixedPriceLBPoolDynamicData() public view {
        FixedPriceLBPoolDynamicData memory data = IFixedPriceLBPool(pool).getFixedPriceLBPoolDynamicData();

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
    }

    function testGetFixedPriceLBPoolImmutableData() public view {
        FixedPriceLBPoolImmutableData memory data = IFixedPriceLBPool(pool).getFixedPriceLBPoolImmutableData();

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
        (pool, ) = _createFixedPriceLBPool(
            address(0), // Pool creator
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
