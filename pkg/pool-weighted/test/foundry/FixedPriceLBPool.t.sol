// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import {
    IUnbalancedLiquidityInvariantRatioBounds
} from "@balancer-labs/v3-interfaces/contracts/vault/IUnbalancedLiquidityInvariantRatioBounds.sol";
import { ISenderGuard } from "@balancer-labs/v3-interfaces/contracts/vault/ISenderGuard.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import "@balancer-labs/v3-interfaces/contracts/pool-weighted/IFixedPriceLBPool.sol";
import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPCommon.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { FixedPriceLBPoolContractsDeployer } from "./utils/FixedPriceLBPoolContractsDeployer.sol";
import { FixedPriceLBPoolFactory } from "../../contracts/lbp/FixedPriceLBPoolFactory.sol";
import { GradualValueChange } from "../../contracts/lib/GradualValueChange.sol";
import { FixedPriceLBPool } from "../../contracts/lbp/FixedPriceLBPool.sol";
import { BaseLBPFactory } from "../../contracts/lbp/BaseLBPFactory.sol";
import { LBPValidation } from "../../contracts/lbp/LBPValidation.sol";
import { LBPCommon } from "../../contracts/lbp/LBPCommon.sol";
import { BaseLBPTest } from "./utils/BaseLBPTest.sol";

contract FixedPriceLBPoolTest is BaseLBPTest, FixedPriceLBPoolContractsDeployer {
    using ArrayHelpers for *;
    using CastingHelpers for address[];
    using FixedPoint for uint256;

    uint256 internal constant DEFAULT_RATE = FixedPoint.ONE;

    // Bounds on the project token rate.
    uint256 private constant MIN_PROJECT_TOKEN_RATE = FixedPoint.ONE / 10_000;
    uint256 private constant MAX_PROJECT_TOKEN_RATE = FixedPoint.ONE * 10_000;

    // Tolerance for initialization balance validation in the buy/sell case.
    uint256 private constant INITIALIZATION_TOLERANCE_PERCENTAGE = 10e16; // 10%

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
            address(router)
        );
        vm.label(address(lbPoolFactory), "Fixed Price LB pool factory");

        return address(lbPoolFactory);
    }

    function createPool() internal virtual override returns (address newPool, bytes memory poolArgs) {
        return
            _createFixedPriceLBPool(
                uint32(block.timestamp + DEFAULT_START_OFFSET),
                uint32(block.timestamp + DEFAULT_END_OFFSET)
            );
    }

    function initPool() internal virtual override {
        vm.startPrank(bob); // Bob is the owner of the pool.
        _initPool(pool, _computeInitAmounts(), 0);
        vm.stopPrank();
    }

    /********************************************************
                        Pool Constructor
    ********************************************************/

    function testCreatePoolTimeTravel() public {
        uint32 startTime = uint32(block.timestamp + 2 * LBPValidation.INITIALIZATION_PERIOD);
        uint32 endTime = uint32(block.timestamp + LBPValidation.INITIALIZATION_PERIOD);

        vm.expectRevert(abi.encodeWithSelector(GradualValueChange.InvalidStartTime.selector, startTime, endTime));
        _createFixedPriceLBPool(
            startTime,
            endTime // EndTime after StartTime, it should revert
        );
    }

    function testCreatePoolTimeTravelWrongEndTime() public {
        uint32 startTime = uint32(block.timestamp + LBPValidation.INITIALIZATION_PERIOD);
        uint32 endTime = startTime - 1;

        vm.expectRevert(abi.encodeWithSelector(GradualValueChange.InvalidStartTime.selector, startTime, endTime));
        _createFixedPriceLBPool(
            startTime,
            endTime // EndTime = StartTime, it should revert
        );
    }

    function testCreatePoolEvents() public {
        uint32 startTime = uint32(block.timestamp + DEFAULT_START_OFFSET);
        uint32 endTime = uint32(block.timestamp + DEFAULT_END_OFFSET);

        uint256 preCreateSnapshotId = vm.snapshotState();

        (address newPool, ) = _createFixedPriceLBPool(startTime, endTime);

        vm.revertToState(preCreateSnapshotId);

        vm.expectEmit();
        emit FixedPriceLBPoolFactory.FixedPriceLBPoolCreated(newPool, bob, startTime, endTime, DEFAULT_RATE);

        vm.expectEmit();
        emit BaseLBPFactory.LBPoolCreated(newPool, projectToken, reserveToken);

        _createFixedPriceLBPool(startTime, endTime);
    }

    function testGetProjectTokenRate() public view {
        assertEq(IFixedPriceLBPool(address(pool)).getProjectTokenRate(), DEFAULT_RATE, "Wrong project token rate");
    }

    function testCreatePoolRates() public {
        uint32 startTime = uint32(block.timestamp + DEFAULT_START_OFFSET);
        uint32 endTime = uint32(block.timestamp + DEFAULT_END_OFFSET);

        LBPCommonParams memory lbpCommonParams = LBPCommonParams({
            name: "FixedPriceLBPool",
            symbol: "FLBP",
            owner: bob,
            projectToken: projectToken,
            reserveToken: reserveToken,
            startTime: startTime,
            endTime: endTime,
            blockProjectTokenSwapsIn: false
        });

        FactoryParams memory factoryParams = FactoryParams({
            vault: vault,
            trustedRouter: address(router),
            poolVersion: poolVersion
        });

        vm.expectRevert(IFixedPriceLBPool.InvalidProjectTokenRate.selector);
        new FixedPriceLBPool(lbpCommonParams, factoryParams, 0);
    }

    function testCreatePoolBiDirectional() public {
        uint32 startTime = uint32(block.timestamp + DEFAULT_START_OFFSET);
        uint32 endTime = uint32(block.timestamp + DEFAULT_END_OFFSET);

        LBPCommonParams memory lbpCommonParams = LBPCommonParams({
            name: "FixedPriceLBPool",
            symbol: "FLBP",
            owner: bob,
            projectToken: projectToken,
            reserveToken: reserveToken,
            startTime: startTime,
            endTime: endTime,
            blockProjectTokenSwapsIn: false
        });

        FactoryParams memory factoryParams = FactoryParams({
            vault: vault,
            trustedRouter: address(router),
            poolVersion: poolVersion
        });

        vm.expectRevert(IFixedPriceLBPool.TokenSwapsInUnsupported.selector);
        new FixedPriceLBPool(lbpCommonParams, factoryParams, DEFAULT_RATE);
    }

    /********************************************************
                            Getters
    ********************************************************/

    function testGetTrustedRouter() public view {
        assertEq(ILBPCommon(pool).getTrustedRouter(), address(router), "Wrong trusted router");
    }

    function testGetProjectToken() public view {
        assertEq(address(ILBPCommon(pool).getProjectToken()), address(projectToken), "Wrong project token");
    }

    function testGetReserveToken() public view {
        assertEq(address(ILBPCommon(pool).getReserveToken()), address(reserveToken), "Wrong reserve token");
    }

    function testGetMinimumInvariantRatio() public view {
        assertEq(
            IUnbalancedLiquidityInvariantRatioBounds(address(pool)).getMinimumInvariantRatio(),
            0,
            "MinInvariantRatio non-zero"
        );
    }

    function testGetMaximumInvariantRatio() public view {
        assertEq(
            IUnbalancedLiquidityInvariantRatioBounds(address(pool)).getMaximumInvariantRatio(),
            type(uint256).max,
            "Wrong MaxInvariantRatio"
        );
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
        (address newPoolSwapEnabled, ) = _createFixedPriceLBPool(
            uint32(block.timestamp + DEFAULT_START_OFFSET),
            uint32(block.timestamp + DEFAULT_END_OFFSET)
        );

        assertTrue(
            ILBPCommon(newPoolSwapEnabled).isProjectTokenSwapInBlocked(),
            "Swap of Project Token in is not blocked"
        );
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

        // Check start and end times
        assertEq(data.startTime, block.timestamp + DEFAULT_START_OFFSET, "Start time mismatch");
        assertEq(data.endTime, block.timestamp + DEFAULT_END_OFFSET, "End time mismatch");

        assertEq(data.projectTokenRate, DEFAULT_RATE, "Wrong project token rate");
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

    function testOnSwap() public {
        // Warp to when swaps are enabled
        vm.warp(block.timestamp + DEFAULT_START_OFFSET + 1);

        uint256 amount = 1e18;

        // Create swap request params - swapping reserve token for project token
        PoolSwapParams memory request = PoolSwapParams({
            kind: SwapKind.EXACT_IN,
            amountGivenScaled18: amount,
            balancesScaled18: vault.getCurrentLiveBalances(pool),
            indexIn: reserveIdx,
            indexOut: projectIdx,
            router: address(router),
            userData: bytes("")
        });

        // Mock vault call to onSwap
        vm.prank(address(vault));
        uint256 amountCalculated = IBasePool(pool).onSwap(request);

        // Verify amount calculated is the same as the amount given.
        assertEq(amountCalculated, amount, "Swap amount should match amount given (buy project)");

        request = PoolSwapParams({
            kind: SwapKind.EXACT_OUT,
            amountGivenScaled18: amount,
            balancesScaled18: vault.getCurrentLiveBalances(pool),
            indexIn: projectIdx,
            indexOut: reserveIdx,
            router: address(router),
            userData: bytes("")
        });

        vm.expectRevert(LBPCommon.SwapOfProjectTokenIn.selector);
        vm.prank(address(vault));
        amountCalculated = IBasePool(pool).onSwap(request);
    }

    function testMultipleSwap() public {
        uint32 startTime = uint32(block.timestamp + DEFAULT_START_OFFSET);
        uint32 endTime = uint32(block.timestamp + DEFAULT_END_OFFSET);

        // Use non-unitary rate
        uint256 rate = 2.5e18;

        (address newPool, ) = _createFixedPriceLBPool(address(0), startTime, endTime, rate);

        // Warp to when swaps are enabled
        vm.warp(block.timestamp + DEFAULT_START_OFFSET + 1);

        uint256 amount = 1e18;

        // Create swap request params - swapping reserve token for project token
        PoolSwapParams memory request = PoolSwapParams({
            kind: SwapKind.EXACT_IN,
            amountGivenScaled18: amount,
            balancesScaled18: vault.getCurrentLiveBalances(pool),
            indexIn: reserveIdx,
            indexOut: projectIdx,
            router: address(router),
            userData: bytes("")
        });

        // Ensure different swap amounts use the same rate
        for (uint256 i = 0; i < 5; ++i) {
            // Mock vault call to onSwap
            vm.prank(address(vault));
            uint256 amountCalculated = IBasePool(newPool).onSwap(request);

            // Verify amount calculated is the same as the amount given
            assertEq(amountCalculated, amount.divDown(rate), "Swap amount should match amount given / rate");

            amount *= 2;
            request.amountGivenScaled18 = amount;
        }
    }

    function testMultipleSwap__Fuzz(uint256 rate, uint256 amountOut) public {
        uint32 startTime = uint32(block.timestamp + DEFAULT_START_OFFSET);
        uint32 endTime = uint32(block.timestamp + DEFAULT_END_OFFSET);

        // Use non-unitary rate
        rate = bound(rate, 1e16, 100e18);
        amountOut = bound(amountOut, 1e18, poolInitAmount / 3);

        (address newPool, ) = _createFixedPriceLBPool(address(0), startTime, endTime, rate);
        vault.manualSetStaticSwapFeePercentage(newPool, 0);

        vm.startPrank(bob); // Bob is the owner of the pool
        _initPool(newPool, _computeInitAmounts(), 0);
        vm.stopPrank();

        uint256 swapAmount = amountOut.mulUp(rate);
        uint256 expectedAmountOut = swapAmount.divDown(rate);

        // Warp to when swaps are enabled
        vm.warp(block.timestamp + DEFAULT_START_OFFSET + 1);

        vm.startPrank(alice);
        uint256 calculatedProjectTokenOut = router.swapSingleTokenExactIn(
            address(newPool),
            reserveToken,
            projectToken,
            swapAmount,
            0,
            MAX_UINT256,
            false,
            bytes("")
        );

        assertEq(calculatedProjectTokenOut, expectedAmountOut, "ExactIn swap output mismatch");

        uint256 calculatedReserveTokenIn = router.swapSingleTokenExactOut(
            address(newPool),
            reserveToken,
            projectToken,
            expectedAmountOut,
            MAX_UINT256,
            MAX_UINT256,
            false,
            bytes("")
        );
        vm.stopPrank();

        // ExactOut rounds up, so it should require >= the original input.
        assertGe(calculatedReserveTokenIn, swapAmount, "ExactOut required less than ExactIn");
        assertApproxEqAbs(swapAmount, calculatedReserveTokenIn, 1, "ExactIn/Out differ by more than rounding");
    }

    function testRunSale() public {
        // Warp to when swaps are enabled
        vm.warp(block.timestamp + DEFAULT_START_OFFSET + 1);

        // Buy half the tokens
        uint256 swapAmount = poolInitAmount / 2;

        vm.prank(alice);
        uint256 swapAmountOut = router.swapSingleTokenExactIn(
            address(pool),
            reserveToken,
            projectToken,
            swapAmount,
            0,
            MAX_UINT256,
            false,
            bytes("")
        );

        // Verify amount calculated is the same as the amount given.
        assertEq(swapAmountOut, swapAmount.mulDown(DEFAULT_SWAP_FEE_PERCENTAGE.complement()), "Wrong amount out");

        // Now bob should be able to withdraw.
        uint256 bptAmountIn = IERC20(pool).balanceOf(bob);

        vm.warp(block.timestamp + DEFAULT_END_OFFSET + 1);

        // Can only withdraw proportionally (since `computeBalance` isn't implemented).
        vm.expectRevert(IVaultErrors.DoesNotSupportUnbalancedLiquidity.selector);
        vm.prank(bob);
        router.removeLiquiditySingleTokenExactIn(address(pool), bptAmountIn, reserveToken, 1, false, bytes(""));

        vm.prank(bob);
        uint256[] memory amountsOut = router.removeLiquidityProportional(
            address(pool),
            bptAmountIn,
            [uint256(0), uint256(0)].toMemoryArray(),
            false,
            bytes("")
        );

        // Pool state after swap.
        uint256 projectInPool = poolInitAmount - swapAmountOut; // 505
        uint256 reserveInPool = swapAmount; // 500

        // Total supply = initial invariant = poolInitAmount (since rate is 1:1).
        uint256 totalSupply = poolInitAmount;

        // Expected proportional amounts (accounting for locked 1e6 minimum BPT)
        uint256 expectedProjectOut = (projectInPool * bptAmountIn) / totalSupply;
        uint256 expectedReserveOut = (reserveInPool * bptAmountIn) / totalSupply;

        assertEq(amountsOut[projectIdx], expectedProjectOut, "Wrong project token amount");
        assertEq(amountsOut[reserveIdx], expectedReserveOut, "Wrong reserve token amount");
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
            "onBeforeInitialize should return false when sender is not owner"
        );
    }

    function testOnBeforeInitialize() public {
        // Warp to before start time (initialization is allowed before start time)
        vm.warp(block.timestamp + DEFAULT_START_OFFSET - 1);

        vm.prank(address(vault));
        _mockGetSender(bob);

        assertTrue(
            IHooks(pool).onBeforeInitialize(_computeInitAmounts(), ""),
            "onBeforeInitialize should return true with correct sender and before startTime"
        );
    }

    function testOnBeforeRemoveLiquidityDuringSale() public {
        vm.warp(block.timestamp + DEFAULT_START_OFFSET + 1);

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

    function testOnBeforeRemoveLiquidityBeforeStartTime() public {
        // Warp to just before start time, where removing liquidity is allowed.
        vm.warp(block.timestamp + DEFAULT_START_OFFSET - 1);

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

    function testComputeBalance() public {
        vm.expectRevert(LBPCommon.UnsupportedOperation.selector);
        IBasePool(pool).computeBalance(new uint256[](2), 0, FixedPoint.ONE);
    }

    function testInitializeInvalidProjectOrReserve() public {
        uint32 startTime = uint32(block.timestamp + DEFAULT_START_OFFSET);
        uint32 endTime = uint32(block.timestamp + DEFAULT_END_OFFSET);

        (address newPool, ) = _createFixedPriceLBPool(startTime, endTime);

        uint256[] memory initAmounts = new uint256[](2);

        // Should fail with zero project tokens.
        vm.expectRevert(IFixedPriceLBPool.InvalidInitializationAmount.selector);

        vm.prank(bob);
        router.initialize(newPool, tokens, initAmounts, 0, false, bytes(""));

        initAmounts[projectIdx] = 1e18;
        initAmounts[reserveIdx] = 1e18;

        // Should fail with non-zero reserve tokens.
        vm.expectRevert(IFixedPriceLBPool.InvalidInitializationAmount.selector);

        vm.prank(bob);
        router.initialize(newPool, tokens, initAmounts, 0, false, bytes(""));
    }

    function testDirectDeployValidation() public {
        uint32 startTime = uint32(block.timestamp + DEFAULT_START_OFFSET);
        uint32 endTime = uint32(block.timestamp + DEFAULT_END_OFFSET);

        LBPCommonParams memory lbpCommonParams = LBPCommonParams({
            name: "FixedPriceLBPool",
            symbol: "FLBP",
            owner: address(0),
            projectToken: projectToken,
            reserveToken: reserveToken,
            startTime: startTime,
            endTime: endTime,
            blockProjectTokenSwapsIn: true // all fixed price LBPs are "buy-only"
        });

        FactoryParams memory factoryParams = FactoryParams({
            vault: vault,
            trustedRouter: address(router),
            poolVersion: poolVersion
        });

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new FixedPriceLBPool(lbpCommonParams, factoryParams, DEFAULT_RATE);

        lbpCommonParams.owner = bob;
        lbpCommonParams.projectToken = IERC20(address(0));
        vm.expectRevert(LBPValidation.InvalidProjectToken.selector);
        new FixedPriceLBPool(lbpCommonParams, factoryParams, DEFAULT_RATE);

        lbpCommonParams.projectToken = projectToken;
        lbpCommonParams.reserveToken = IERC20(address(0));
        vm.expectRevert(LBPValidation.InvalidReserveToken.selector);
        new FixedPriceLBPool(lbpCommonParams, factoryParams, DEFAULT_RATE);

        lbpCommonParams.reserveToken = projectToken;
        vm.expectRevert(LBPValidation.TokensMustBeDifferent.selector);
        new FixedPriceLBPool(lbpCommonParams, factoryParams, DEFAULT_RATE);

        lbpCommonParams.reserveToken = reserveToken;
        lbpCommonParams.startTime = lbpCommonParams.endTime + 1;

        vm.expectRevert(
            abi.encodeWithSelector(
                GradualValueChange.InvalidStartTime.selector,
                lbpCommonParams.startTime,
                lbpCommonParams.endTime
            )
        );
        new FixedPriceLBPool(lbpCommonParams, factoryParams, DEFAULT_RATE);
    }

    /*******************************************************************************
                                   Private Helpers
    *******************************************************************************/

    function _mockGetSender(address sender) private {
        vm.mockCall(address(router), abi.encodeWithSelector(ISenderGuard.getSender.selector), abi.encode(sender));
    }

    function _computeInitAmounts() internal view returns (uint256[] memory initAmounts) {
        initAmounts = new uint256[](2);

        initAmounts[projectIdx] = poolInitAmount;
    }

    function _createFixedPriceLBPool(
        uint32 startTime,
        uint32 endTime
    ) internal returns (address newPool, bytes memory poolArgs) {
        return _createFixedPriceLBPool(address(0), startTime, endTime, DEFAULT_RATE);
    }

    function _createFixedPriceLBPool(
        address poolCreator,
        uint32 startTime,
        uint32 endTime,
        uint256 projectTokenRate
    ) internal returns (address newPool, bytes memory poolArgs) {
        LBPCommonParams memory lbpCommonParams = LBPCommonParams({
            name: "FixedPriceLBPool",
            symbol: "FLBP",
            owner: bob,
            projectToken: projectToken,
            reserveToken: reserveToken,
            startTime: startTime,
            endTime: endTime,
            blockProjectTokenSwapsIn: true // all fixed price LBPs are "buy-only"
        });

        FactoryParams memory factoryParams = FactoryParams({
            vault: vault,
            trustedRouter: address(router),
            poolVersion: poolVersion
        });

        uint256 salt = _saltCounter++;
        address poolCreator_ = poolCreator;

        newPool = lbPoolFactory.create(lbpCommonParams, projectTokenRate, swapFee, bytes32(salt), poolCreator_);

        poolArgs = abi.encode(lbpCommonParams, factoryParams, projectTokenRate);
    }
}
