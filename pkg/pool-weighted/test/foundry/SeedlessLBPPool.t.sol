// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { ILBPool, LBPoolImmutableData } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPool.sol";
import { PoolConfig, Rounding, TokenInfo } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { LBPParams } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPool.sol";
import { IPoolInfo } from "@balancer-labs/v3-interfaces/contracts/pool-utils/IPoolInfo.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";

import { WeightedMath } from "@balancer-labs/v3-solidity-utils/contracts/math/WeightedMath.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { WeightedLBPTest } from "./utils/WeightedLBPTest.sol";
import { LBPCommon } from "../../contracts/lbp/LBPCommon.sol";
import { LBPool } from "../../contracts/lbp/LBPool.sol";

contract SeedlessLBPTest is WeightedLBPTest {
    using FixedPoint for uint256;

    function setUp() public virtual override {
        reserveTokenVirtualBalance = poolInitAmount;

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

    function initPool() internal virtual override {
        // Initialize without reserve tokens
        uint256[] memory initAmounts = new uint256[](2);
        initAmounts[projectIdx] = poolInitAmount;

        vm.startPrank(bob); // Bob is the owner of the pool.
        _initPool(pool, initAmounts, 0); // Zero reserve tokens
        vm.stopPrank();
    }

    /*******************************************************************************
                                    Initialization
    *******************************************************************************/

    function testVirtualBalanceIsSet() public view {
        uint256 virtualBalance = ILBPool(pool).getReserveTokenVirtualBalance();
        assertEq(virtualBalance, poolInitAmount, "Pool virtual balance should equal the init amount");
    }

    function testValidSeedlessInitialization() public view {
        // Verify pool is initialized
        PoolConfig memory poolConfig = vault.getPoolConfig(pool);
        assertTrue(poolConfig.isPoolInitialized, "Pool should be initialized");

        // Verify balances
        uint256[] memory balances = vault.getCurrentLiveBalances(pool);
        assertEq(balances[projectIdx], poolInitAmount, "Project token balance mismatch");
        assertEq(balances[reserveIdx], 0, "Reserve token balance should be zero");
    }

    function testSeedlessInitializationWithNonZeroReserve() public {
        assertGt(poolInitAmount, 0, "Sanity check");

        // Create a new seedless pool
        (address newPool, ) = _createLBPool(
            address(0),
            uint32(block.timestamp + DEFAULT_START_OFFSET),
            uint32(block.timestamp + DEFAULT_END_OFFSET),
            DEFAULT_PROJECT_TOKENS_SWAP_IN
        );

        // Try to initialize with reserve tokens
        uint256[] memory initAmounts = new uint256[](2);
        initAmounts[projectIdx] = poolInitAmount;
        initAmounts[reserveIdx] = poolInitAmount;

        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(newPool);

        vm.expectRevert(ILBPool.SeedlessLBPInitializationWithNonZeroReserve.selector);
        vm.prank(bob);
        router.initialize(newPool, tokens, initAmounts, 0, false, bytes(""));
    }

    /*******************************************************************************
                                    Swap Tests
    *******************************************************************************/

    function testSwapBuyProjectToken() public {
        // Validate pre-condition: first buy from a seedless LBP should have no reserves
        uint256[] memory balances = vault.getCurrentLiveBalances(pool);
        assertEq(balances[reserveIdx], 0, "Non-zero real reserve balance");

        // Warp to when swaps are enabled
        vm.warp(block.timestamp + DEFAULT_START_OFFSET + 1);

        uint256 swapAmount = 1e18;

        // User swaps reserve tokens for project tokens
        uint256 projectBalanceBefore = projectToken.balanceOf(alice);
        uint256 reserveBalanceBefore = reserveToken.balanceOf(alice);

        vm.prank(alice);
        router.swapSingleTokenExactIn(
            pool,
            reserveToken,
            projectToken,
            swapAmount,
            0, // minAmountOut
            type(uint256).max,
            false,
            bytes("")
        );

        uint256 projectReceived = projectToken.balanceOf(alice) - projectBalanceBefore;
        uint256 reserveSpent = reserveBalanceBefore - reserveToken.balanceOf(alice);

        assertGt(projectReceived, 0, "Should receive project tokens");
        assertEq(reserveSpent, swapAmount, "Reserve spent mismatch");

        // Verify pool now has real reserve balance
        balances = vault.getCurrentLiveBalances(pool);
        assertGt(balances[reserveIdx], 0, "Pool should now have real reserve balance");
    }

    function testSwapSellProjectTokenWithReserve() public {
        // Deploy pool with bidirectional swaps enabled
        (pool, ) = _createLBPoolWithCustomWeights(
            address(0),
            startWeights[projectIdx],
            startWeights[reserveIdx],
            endWeights[projectIdx],
            endWeights[reserveIdx],
            uint32(block.timestamp + DEFAULT_START_OFFSET),
            uint32(block.timestamp + DEFAULT_END_OFFSET),
            false // Allow project token swaps in
        );
        initPool();

        // Warp to when swaps are enabled
        vm.warp(block.timestamp + DEFAULT_START_OFFSET);

        uint256 buyAmount = 10e18; // Must be >> sellAmount
        uint256 sellAmount = 1e18;

        // First, user buys project tokens to build real reserve
        vm.prank(bob);
        router.swapSingleTokenExactIn(
            pool,
            reserveToken,
            projectToken,
            buyAmount,
            0,
            type(uint256).max,
            false,
            bytes("")
        );

        uint256 reserveBalanceBefore = reserveToken.balanceOf(alice);

        vm.prank(alice);
        router.swapSingleTokenExactIn(
            pool,
            projectToken,
            reserveToken,
            sellAmount,
            0,
            type(uint256).max,
            false,
            bytes("")
        );

        uint256 reserveReceived = reserveToken.balanceOf(alice) - reserveBalanceBefore;

        assertGt(reserveReceived, 0, "Should receive reserve tokens");
    }

    function testSwapSellProjectTokenExceedsReserves() public {
        // Deploy pool with bidirectional swaps enabled
        (pool, ) = _createLBPoolWithCustomWeights(
            address(0),
            startWeights[projectIdx],
            startWeights[reserveIdx],
            endWeights[projectIdx],
            endWeights[reserveIdx],
            uint32(block.timestamp + DEFAULT_START_OFFSET),
            uint32(block.timestamp + DEFAULT_END_OFFSET),
            false // Allow project token swaps in
        );
        initPool();

        // Warp to when swaps are enabled
        vm.warp(block.timestamp + DEFAULT_START_OFFSET);

        uint256 buyAmount = 1e18;
        uint256 sellAmount = 10e18; // Should fail with sellAmount >> buyAmount

        // First, user buys project tokens to build real reserve
        vm.prank(bob);
        router.swapSingleTokenExactIn(
            pool,
            reserveToken,
            projectToken,
            buyAmount,
            0,
            type(uint256).max,
            false,
            bytes("")
        );

        uint256 snapshotId = vm.snapshotState();

        uint256[] memory balances = vault.getCurrentLiveBalances(pool);

        uint256 effectiveReserveBalance = balances[reserveIdx] + reserveTokenVirtualBalance;

        uint256 expectedAmountOut = WeightedMath.computeOutGivenExactIn(
            balances[projectIdx],
            startWeights[projectIdx],
            effectiveReserveBalance,
            startWeights[reserveIdx],
            sellAmount.mulDown(DEFAULT_SWAP_FEE_PERCENTAGE.complement())
        );

        vm.revertToState(snapshotId);

        vm.expectRevert(
            abi.encodeWithSelector(
                ILBPool.InsufficientRealReserveBalance.selector,
                expectedAmountOut,
                balances[reserveIdx]
            )
        );
        vm.prank(alice);
        router.swapSingleTokenExactIn(
            pool,
            projectToken,
            reserveToken,
            sellAmount,
            0,
            type(uint256).max,
            false,
            bytes("")
        );
    }

    /*******************************************************************************
                                    Price Verification
    *******************************************************************************/

    function testPriceUsesVirtualBalance() public {
        vm.warp(block.timestamp + DEFAULT_START_OFFSET);
        vault.manualUnsafeSetStaticSwapFeePercentage(pool, 0);

        uint256[] memory realBalances = vault.getCurrentLiveBalances(pool);
        assertEq(realBalances[reserveIdx], 0, "Non-zero reserve balance");

        uint256 effectiveReserve = realBalances[reserveIdx] + reserveTokenVirtualBalance;
        uint256 swapAmount = 1e15;

        // Price of project in reserve terms should use effective reserve
        // spot price = (reserveBalance / reserveWeight) / (projectBalance / projectWeight)
        uint256 expectedSpotPrice = effectiveReserve.divDown(startWeights[reserveIdx]).divDown(
            realBalances[projectIdx].divDown(startWeights[projectIdx])
        );

        // Calculate expected output using the same math as the pool
        uint256 expectedProjectOut = WeightedMath.computeOutGivenExactIn(
            effectiveReserve, // balanceIn (reserve with virtual)
            startWeights[reserveIdx], // weightIn
            realBalances[projectIdx], // balanceOut (project)
            startWeights[projectIdx], // weightOut
            swapAmount // amountIn - no fee (set to 0 above)
        );

        uint256 projectBefore = projectToken.balanceOf(alice);

        vm.prank(alice);
        router.swapSingleTokenExactIn(
            pool,
            reserveToken,
            projectToken,
            swapAmount,
            0,
            type(uint256).max,
            false,
            bytes("")
        );

        uint256 projectReceived = projectToken.balanceOf(alice) - projectBefore;
        assertEq(projectReceived, expectedProjectOut, "Wrong received amount");

        uint256 effectivePrice = swapAmount.divDown(projectReceived);
        assertApproxEqAbs(effectivePrice, expectedSpotPrice, 1e13, "Wrong effective price");
    }

    /*******************************************************************************
                                    Immutable Data
    *******************************************************************************/

    function testGetLBPoolImmutableData() public view {
        LBPoolImmutableData memory data = ILBPool(pool).getLBPoolImmutableData();

        // Check tokens array matches pool tokens
        IERC20[] memory poolTokens = vault.getPoolTokens(pool);
        assertEq(data.tokens.length, poolTokens.length, "Tokens length mismatch");
        assertEq(data.tokens.length, 2, "Not two tokens");
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

        assertEq(
            data.reserveTokenVirtualBalance,
            reserveTokenVirtualBalance,
            "Wrong reserve token balance (immutable data)"
        );
    }

    /*******************************************************************************
                                Liquidity Operations
    *******************************************************************************/

    function testProportionalAddBeforeSale() public {
        uint256[] memory balancesBefore = vault.getCurrentLiveBalances(pool);
        uint256 totalSupplyBefore = IERC20(pool).totalSupply();

        uint256[] memory maxAmountsIn = new uint256[](2);
        maxAmountsIn[projectIdx] = poolInitAmount;
        maxAmountsIn[reserveIdx] = 0; // No reserve tokens expected

        uint256 bptBefore = IERC20(pool).balanceOf(bob);
        uint256 projectBefore = projectToken.balanceOf(bob);
        uint256 reserveBefore = reserveToken.balanceOf(bob);

        vm.prank(bob);
        router.addLiquidityProportional(pool, maxAmountsIn, 1, false, bytes(""));

        uint256 bptReceived = IERC20(pool).balanceOf(bob) - bptBefore;
        uint256 projectSpent = projectBefore - projectToken.balanceOf(bob);
        uint256 reserveSpent = reserveBefore - reserveToken.balanceOf(bob);

        // With real balances [P, 0], proportional add should require 0 reserve
        assertEq(reserveSpent, 0, "Should not spend any reserve tokens");

        // BPT received should be proportional: bptOut = totalSupply * amountIn / balance
        uint256 expectedBpt = (totalSupplyBefore * projectSpent) / balancesBefore[projectIdx];
        assertApproxEqAbs(bptReceived, expectedBpt, 1, "BPT amount mismatch");
    }

    function testProportionalRemoveAfterSale() public {
        // Do a swap to accumulate real reserve
        vm.warp(block.timestamp + DEFAULT_START_OFFSET + 1);

        uint256 buyAmount = 100e18;
        vm.prank(alice);
        router.swapSingleTokenExactIn(
            pool,
            reserveToken,
            projectToken,
            buyAmount,
            0,
            type(uint256).max,
            false,
            bytes("")
        );

        // Warp to after sale
        vm.warp(block.timestamp + DEFAULT_END_OFFSET + 1);

        // Record state before withdrawal
        uint256[] memory balancesBefore = vault.getCurrentLiveBalances(pool);
        uint256 totalSupplyBefore = IERC20(pool).totalSupply();
        uint256 bptBalance = IERC20(pool).balanceOf(bob);

        uint256 projectBefore = projectToken.balanceOf(bob);
        uint256 reserveBefore = reserveToken.balanceOf(bob);

        uint256[] memory minAmountsOut = new uint256[](2);
        vm.prank(bob);
        router.removeLiquidityProportional(pool, bptBalance, minAmountsOut, false, bytes(""));

        uint256 projectReceived = projectToken.balanceOf(bob) - projectBefore;
        uint256 reserveReceived = reserveToken.balanceOf(bob) - reserveBefore;

        // Calculate expected: balances * bptIn / totalSupply (rounds down)
        uint256 expectedProject = (balancesBefore[projectIdx] * bptBalance) / totalSupplyBefore;
        uint256 expectedReserve = (balancesBefore[reserveIdx] * bptBalance) / totalSupplyBefore;

        assertEq(projectReceived, expectedProject, "Project token amount mismatch");
        assertEq(reserveReceived, expectedReserve, "Reserve token amount mismatch");

        // Verify only minimum supply remains
        assertEq(IERC20(pool).totalSupply(), POOL_MINIMUM_TOTAL_SUPPLY, "Should only have minimum supply left");

        // Verify remaining balances are ONLY dust from minimum supply, not from virtual balance
        uint256[] memory balancesAfter = vault.getCurrentLiveBalances(pool);

        // Dust should be proportional to minimum supply fraction
        uint256 dustFraction = (POOL_MINIMUM_TOTAL_SUPPLY * 1e18) / totalSupplyBefore;
        uint256 expectedDustProject = (balancesBefore[projectIdx] * dustFraction) / 1e18;
        uint256 expectedDustReserve = (balancesBefore[reserveIdx] * dustFraction) / 1e18;

        // Allow small rounding tolerance
        assertApproxEqAbs(balancesAfter[projectIdx], expectedDustProject, 2, "Unexpected project token dust");
        assertApproxEqAbs(balancesAfter[reserveIdx], expectedDustReserve, 2, "Unexpected reserve token dust");

        // Owner should receive all real reserve tokens (minus dust)
        assertEq(reserveReceived + balancesAfter[reserveIdx], balancesBefore[reserveIdx], "Reserve tokens locked!");
    }

    function testSingleTokenExactOutAddProjectToken() public {
        uint256 bptAmountOut = 100e18;
        uint256 maxAmountIn = poolInitAmount;

        vm.expectRevert(LBPCommon.UnsupportedOperation.selector);
        vm.prank(bob);
        router.addLiquiditySingleTokenExactOut(pool, projectToken, maxAmountIn, bptAmountOut, false, bytes(""));
    }

    function testSingleTokenExactOutAddReserveToken() public {
        uint256 bptAmountOut = 100e18;
        uint256 maxAmountIn = poolInitAmount;

        vm.expectRevert(LBPCommon.UnsupportedOperation.selector);
        vm.prank(bob);
        router.addLiquiditySingleTokenExactOut(pool, reserveToken, maxAmountIn, bptAmountOut, false, bytes(""));
    }

    function testSingleTokenExactInRemoveProjectToken() public {
        vm.warp(block.timestamp + DEFAULT_START_OFFSET);

        uint256 buyAmount = 10e18;

        vm.prank(alice);
        router.swapSingleTokenExactIn(
            pool,
            reserveToken,
            projectToken,
            buyAmount,
            0,
            type(uint256).max,
            false,
            bytes("")
        );

        // Warp to after sale
        vm.warp(block.timestamp + DEFAULT_END_OFFSET + 1);

        vm.expectRevert(LBPCommon.UnsupportedOperation.selector);
        vm.prank(bob);
        router.removeLiquiditySingleTokenExactIn(
            pool,
            1e18,
            projectToken,
            1, // minAmountOut
            false,
            bytes("")
        );
    }

    function testSingleTokenExactInRemoveReserveToken() public {
        vm.warp(block.timestamp + DEFAULT_START_OFFSET);

        // Need enough reserve in pool to support removal
        uint256 buyAmount = 100e18;

        vm.prank(alice);
        router.swapSingleTokenExactIn(
            pool,
            reserveToken,
            projectToken,
            buyAmount,
            0,
            type(uint256).max,
            false,
            bytes("")
        );

        // Warp to after sale
        vm.warp(block.timestamp + DEFAULT_END_OFFSET + 1);

        vm.expectRevert(LBPCommon.UnsupportedOperation.selector);
        vm.prank(bob);
        router.removeLiquiditySingleTokenExactIn(
            pool,
            1e18,
            reserveToken,
            1, // minAmountOut
            false,
            bytes("")
        );
    }

    /*******************************************************************************
                                Invariant Tests
    *******************************************************************************/

    function testComputeInvariantUsesEffectiveBalances() public view {
        uint256[] memory realBalances = vault.getCurrentLiveBalances(pool);

        // Compute invariant via pool (should use effective balances)
        uint256 poolInvariant = IBasePool(pool).computeInvariant(realBalances, Rounding.ROUND_DOWN);

        // Compute expected invariant with effective balances
        uint256[] memory effectiveBalances = new uint256[](2);
        effectiveBalances[projectIdx] = realBalances[projectIdx];
        effectiveBalances[reserveIdx] = realBalances[reserveIdx] + reserveTokenVirtualBalance;

        uint256 expectedInvariant = WeightedMath.computeInvariantDown(startWeights, effectiveBalances);

        assertEq(poolInvariant, expectedInvariant, "Invariant should use effective balances");
    }

    /*******************************************************************************
                                    End-to-End Sale
    *******************************************************************************/

    function testEndToEndSale() public {
        uint256[] memory initialBalances = vault.getCurrentLiveBalances(pool);
        assertEq(initialBalances[reserveIdx], 0, "Should start with 0 real reserve");

        vm.warp(block.timestamp + DEFAULT_START_OFFSET + 1);

        // Multiple buys
        uint256 totalBought = 0;
        for (uint256 i = 0; i < 5; i++) {
            uint256 buyAmount = 5e18 * (i + 1);

            vm.prank(alice);
            router.swapSingleTokenExactIn(
                pool,
                reserveToken,
                projectToken,
                buyAmount,
                0,
                type(uint256).max,
                false,
                bytes("")
            );

            totalBought += buyAmount;
        }

        // Check reserve accumulated
        uint256[] memory midBalances = vault.getCurrentLiveBalances(pool);
        assertApproxEqRel(midBalances[reserveIdx], totalBought, 0.01e18, "Reserve should accumulate from buys");

        vm.warp(block.timestamp + DEFAULT_END_OFFSET + 1);

        // Owner withdraws proceeds
        uint256 bptBalance = IERC20(pool).balanceOf(bob);
        uint256 reserveBefore = reserveToken.balanceOf(bob);
        uint256 projectBefore = projectToken.balanceOf(bob);

        uint256[] memory minAmountsOut = new uint256[](2);
        vm.prank(bob);
        router.removeLiquidityProportional(pool, bptBalance, minAmountsOut, false, bytes(""));

        uint256 reserveReceived = reserveToken.balanceOf(bob) - reserveBefore;
        uint256 projectReceived = projectToken.balanceOf(bob) - projectBefore;

        // Owner should get all the accumulated reserve (proceeds) and remaining project tokens
        assertApproxEqRel(reserveReceived, totalBought, 0.01e18, "Owner should receive sale proceeds");
        assertGt(projectReceived, 0, "Owner should receive remaining project tokens");
    }

    /*******************************************************************************
                                    PoolInfo Functions
    *******************************************************************************/

    function testGetCurrentLiveBalancesIncludesVirtual() public view {
        uint256[] memory poolBalances = IPoolInfo(pool).getCurrentLiveBalances();
        uint256[] memory vaultBalances = vault.getCurrentLiveBalances(pool);

        assertEq(poolBalances[projectIdx], vaultBalances[projectIdx], "Project balance mismatch");
        assertEq(
            poolBalances[reserveIdx],
            vaultBalances[reserveIdx] + reserveTokenVirtualBalance,
            "Reserve should include virtual"
        );
    }

    function testGetTokenInfoIncludesVirtual() public view {
        (, , uint256[] memory balancesRaw, uint256[] memory lastBalancesLiveScaled18) = IPoolInfo(pool).getTokenInfo();

        (, , uint256[] memory realBalancesRaw, uint256[] memory realLastBalancesLiveScaled18) = vault.getPoolTokenInfo(
            pool
        );

        assertEq(balancesRaw[projectIdx], realBalancesRaw[projectIdx], "Project raw balance mismatch");
        assertEq(
            lastBalancesLiveScaled18[projectIdx],
            realLastBalancesLiveScaled18[projectIdx],
            "Project live balance mismatch"
        );

        assertEq(
            balancesRaw[reserveIdx],
            realBalancesRaw[reserveIdx] + reserveTokenVirtualBalance,
            "Reserve raw should include virtual"
        );
        assertEq(
            lastBalancesLiveScaled18[reserveIdx],
            realLastBalancesLiveScaled18[reserveIdx] + reserveTokenVirtualBalance,
            "Reserve live should include virtual"
        );
    }

    function testGetCurrentLiveBalancesNonSeedless() public {
        // Create a non-seedless pool
        reserveTokenVirtualBalance = 0;

        (address nonSeedlessPool, ) = _createLBPool(
            address(0),
            uint32(block.timestamp + DEFAULT_START_OFFSET),
            uint32(block.timestamp + DEFAULT_END_OFFSET),
            DEFAULT_PROJECT_TOKENS_SWAP_IN
        );

        // Initialize with both tokens
        uint256[] memory initAmounts = new uint256[](2);
        initAmounts[projectIdx] = poolInitAmount;
        initAmounts[reserveIdx] = poolInitAmount;

        vm.startPrank(bob);
        _initPool(nonSeedlessPool, initAmounts, 0);
        vm.stopPrank();

        // Pool and vault should return same balances
        uint256[] memory poolBalances = IPoolInfo(nonSeedlessPool).getCurrentLiveBalances();
        uint256[] memory vaultBalances = vault.getCurrentLiveBalances(nonSeedlessPool);

        assertEq(poolBalances[projectIdx], vaultBalances[projectIdx], "Project balance mismatch");
        assertEq(poolBalances[reserveIdx], vaultBalances[reserveIdx], "Reserve balance should match exactly");
    }
}
