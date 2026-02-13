// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { ILBPMigrationRouter } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPMigrationRouter.sol";
import { IWeightedPool } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/IWeightedPool.sol";
import { ILBPool, LBPParams } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPool.sol";
import { IPoolInfo } from "@balancer-labs/v3-interfaces/contracts/pool-utils/IPoolInfo.sol";
import "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPCommon.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ScalingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ScalingHelpers.sol";
import { ERC20TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC20TestToken.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { LBPMigrationRouter } from "../../contracts/lbp/LBPMigrationRouter.sol";
import { BPTTimeLocker } from "../../contracts/lbp/BPTTimeLocker.sol";
import { SpotPriceHelper } from "./utils/SpotPriceHelper.sol";
import { WeightedLBPTest } from "./utils/WeightedLBPTest.sol";

contract LBPMigrationRouterTest is WeightedLBPTest {
    using ArrayHelpers for *;
    using FixedPoint for uint256;
    using ScalingHelpers for uint256;
    using SpotPriceHelper for *;

    uint256 constant USDC6_SCALING_FACTOR = 1e12;
    uint256 constant WBTC8_SCALING_FACTOR = 1e10;
    uint256 constant DEFAULT_RATE = 1e18;
    uint256 constant DELTA = 1e7;
    uint256 constant DELTA_REL = 0.0000001e16; // 0.0000001%
    uint256 internal constant DEFAULT_BPT_LOCK_DURATION = 10 days;
    uint256 internal constant DEFAULT_SHARE_TO_MIGRATE = 70e16; // 70% of the pool
    uint256 internal constant DEFAULT_WEIGHT_PROJECT_TOKEN = 30e16; // 30% for project token
    uint256 internal constant DEFAULT_WEIGHT_RESERVE_TOKEN = 70e16; // 70% for reserve token

    uint256 internal constant SEEDLESS_BPT_SHARE_TO_MIGRATE = 80e16;

    string constant POOL_NAME = "Weighted Pool";
    string constant POOL_SYMBOL = "WP";
    string constant VERSION = "LBP Migration Router v1";

    address excessReceiver = makeAddr("excessReceiver");
    // At 70% reserve, 30% project token end weights, the TVL should be 10M, and the spot price should be 100,000.
    uint256 usdc6DecimalsInitAmount = 7_000_000e6;
    uint256 wbtc8DecimalsInitAmount = 30e8;

    function setUp() public virtual override {
        super.setUp();
    }

    function createPool() internal virtual override returns (address newPool, bytes memory poolArgs) {
        return
            _createLBPoolWithMigration(
                address(0), // Pool creator
                DEFAULT_BPT_LOCK_DURATION,
                DEFAULT_SHARE_TO_MIGRATE,
                DEFAULT_WEIGHT_PROJECT_TOKEN,
                DEFAULT_WEIGHT_RESERVE_TOKEN
            );
    }

    function testConstructorWithIncorrectWeightedPoolFactory() external {
        vm.prank(admin);
        balancerContractRegistry.deprecateBalancerContract(address(weightedPoolFactory));

        vm.expectRevert(ILBPMigrationRouter.NoRegisteredWeightedPoolFactory.selector);
        new LBPMigrationRouter(balancerContractRegistry, VERSION);
    }

    function testLockAmount() external {
        uint256 amount = 101e18;
        uint256 duration = 1 days;
        address pool = address(new ERC20TestToken("Pool Token", "PT", 12));

        migrationRouter.manualLockBPT(IERC20(pool), alice, amount, duration);

        uint256 id = migrationRouter.getId(pool);
        uint256 balance = migrationRouter.balanceOf(alice, id);

        assertEq(balance, amount, "Incorrect locked amount");
        assertEq(migrationRouter.getUnlockTimestamp(id), block.timestamp + duration, "Incorrect unlock timestamp");
        assertEq(migrationRouter.decimals(id), IERC20Metadata(pool).decimals(), "Incorrect token decimals");
        assertEq(migrationRouter.name(id), "Locked Pool Token", "Incorrect token name");
        assertEq(migrationRouter.symbol(id), "LOCKED-PT", "Incorrect token symbol");
    }

    function testUnlockAmount() external {
        uint256 amount = 101e18;
        uint256 duration = 1 days;
        ERC20TestToken pool = new ERC20TestToken("Pool Token", "PT", 12);
        uint256 id = migrationRouter.getId(address(pool));

        pool.mint(address(migrationRouter), amount);
        migrationRouter.manualLockBPT(IERC20(pool), alice, amount, duration);

        vm.warp(block.timestamp + duration);
        vm.prank(alice);
        migrationRouter.withdrawBPT(address(pool));

        uint256 aliceWrappedTokenBalanceAfter = migrationRouter.balanceOf(alice, id);
        uint256 aliceTokenBalanceAfter = IERC20(pool).balanceOf(alice);
        uint256 routerTokenBalanceAfter = IERC20(pool).balanceOf(address(migrationRouter));

        assertEq(aliceWrappedTokenBalanceAfter, 0, "Alice's wrapped token balance after unlock is incorrect");
        assertEq(aliceTokenBalanceAfter, amount, "Alice's token balance after unlock is incorrect");
        assertEq(routerTokenBalanceAfter, 0, "Router's token balance after unlock is incorrect");
    }

    function testUnlockAmountRevertsIfAmountIsZero() external {
        vm.expectRevert(BPTTimeLocker.NoLockedBPT.selector);
        migrationRouter.withdrawBPT(address(0));
    }

    function testUnlockAmountRevertsIfUnlockTimestampNotReached() external {
        ERC20TestToken pool = new ERC20TestToken("Pool Token", "PT", 12);
        uint256 unlockTimestamp = block.timestamp + DEFAULT_BPT_LOCK_DURATION;
        migrationRouter.manualLockBPT(pool, alice, 1e10, DEFAULT_BPT_LOCK_DURATION);

        vm.expectRevert(abi.encodePacked(BPTTimeLocker.BPTStillLocked.selector, unlockTimestamp));
        vm.prank(alice);
        migrationRouter.withdrawBPT(address(pool));
    }

    function testMigrateLiquidityWithSpecificParameters() external {
        uint256 weightProjectToken = 80e16;
        uint256 weightReserveToken = 20e16;
        uint256 bptPercentageToMigrate = 50e16;

        (pool, ) = _createLBPoolWithMigration(
            address(0), // Pool creator
            DEFAULT_BPT_LOCK_DURATION,
            bptPercentageToMigrate,
            weightProjectToken,
            weightReserveToken
        );
        initPool();

        vm.startPrank(bob);
        vm.warp(ILBPool(pool).getLBPoolImmutableData().endTime + 1);
        IERC20(pool).approve(address(migrationRouter), IERC20(pool).balanceOf(bob));

        PoolRoleAccounts memory poolRoleAccounts = PoolRoleAccounts({
            pauseManager: makeAddr("pauseManager"),
            swapFeeManager: makeAddr("swapFeeManager"),
            poolCreator: address(0)
        });

        (, , , uint256[] memory poolBalancesBeforeScaled18) = vault.getPoolTokenInfo(pool);

        (IWeightedPool weightedPool, , ) = migrationRouter.migrateLiquidity(
            ILBPool(pool),
            excessReceiver,
            ILBPMigrationRouter.WeightedPoolParams({
                name: POOL_NAME,
                symbol: POOL_SYMBOL,
                roleAccounts: poolRoleAccounts,
                swapFeePercentage: DEFAULT_SWAP_FEE_PERCENTAGE,
                poolHooksContract: address(0),
                enableDonation: false,
                disableUnbalancedLiquidity: false,
                salt: bytes32(0)
            })
        );

        vm.stopPrank();

        uint256[] memory lbpWeights = ILBPool(pool).getLBPoolDynamicData().normalizedWeights;
        assertEq(lbpWeights[projectIdx], 30e16, "LBP weight for project token should be 30%");
        assertEq(lbpWeights[reserveIdx], 70e16, "LBP weight for reserve token should be 70%");

        // New project token weight is > LBP project token weight, so we use all of the project token balance.
        uint256 newBalanceProjectTokenScaled18 = poolBalancesBeforeScaled18[projectIdx];

        // Project token balance represents 30% of the TVL of the LBP, and reserve token balance represents 70%.
        // In the new pool, project token balance represents 80% of the TVL, and reserve token balance represents 20%.
        // Then, 3/10 * TVL1 = 8/10 * TVL2, where TVL1 is the LBP TVL and TVL2 is the new pool TVL.
        // On the other hand, balance[reserve] = 7/10 * TVL1, and newBalance[reserve] = 2/10 * TVL2.
        // Solving for newBalance[reserve], we get:
        // newBalance[reserve] =
        //                 balance[reserve] * newWeightReserve / newWeightProject * oldWeightProject / oldWeightReserve
        uint256 newBalanceReserveTokenScaled18 = poolBalancesBeforeScaled18[reserveIdx]
            .mulDown(weightReserveToken)
            .divDown(weightProjectToken)
            .mulDown(lbpWeights[projectIdx])
            .divDown(lbpWeights[reserveIdx]);

        uint256[] memory expectedPoolBalancesScaled18 = new uint256[](TOKEN_COUNT);
        expectedPoolBalancesScaled18[projectIdx] = newBalanceProjectTokenScaled18.mulDown(bptPercentageToMigrate);
        expectedPoolBalancesScaled18[reserveIdx] = newBalanceReserveTokenScaled18.mulDown(bptPercentageToMigrate);

        // Check that the weighted pool balance is correct
        uint256[] memory poolBalancesAfterScaled18 = vault.getCurrentLiveBalances(address(weightedPool));
        assertApproxEqAbs(
            poolBalancesAfterScaled18[projectIdx],
            expectedPoolBalancesScaled18[projectIdx],
            DELTA,
            "Live balance mismatch for project token"
        );
        assertApproxEqAbs(
            poolBalancesAfterScaled18[reserveIdx],
            expectedPoolBalancesScaled18[reserveIdx],
            DELTA,
            "Live balance mismatch for reserve token"
        );
    }

    function testMigrateLiquidity__Fuzz(uint256 weightReserveToken, uint256 bptPercentageToMigrate) external {
        uint256 minReserveTokenWeight = 20e16; // 20%
        uint256 maxReserveTokenWeight = 100e16 - minReserveTokenWeight;
        weightReserveToken = bound(weightReserveToken, minReserveTokenWeight, maxReserveTokenWeight);

        uint256 weightProjectToken = FixedPoint.ONE - weightReserveToken;
        bptPercentageToMigrate = bound(bptPercentageToMigrate, 10e16, 100e16);

        // Create & Init LBP
        (pool, ) = _createLBPoolWithMigration(
            address(0), // Pool creator
            DEFAULT_BPT_LOCK_DURATION,
            bptPercentageToMigrate,
            weightProjectToken,
            weightReserveToken
        );
        initPool();

        vm.startPrank(bob);

        vm.warp(ILBPool(pool).getLBPoolImmutableData().endTime + 1);
        IERC20(pool).approve(address(migrationRouter), IERC20(pool).balanceOf(bob));

        (
            IERC20[] memory lbpTokens,
            TokenInfo[] memory lbpTokenInfo,
            ,
            uint256[] memory lbpBalancesBeforeScaled18
        ) = vault.getPoolTokenInfo(pool);

        vm.stopPrank();

        ILBPMigrationRouter.WeightedPoolParams memory weightedPoolParams = ILBPMigrationRouter.WeightedPoolParams({
            name: POOL_NAME,
            symbol: POOL_SYMBOL,
            roleAccounts: PoolRoleAccounts({
                pauseManager: makeAddr("pauseManager"),
                swapFeeManager: makeAddr("swapFeeManager"),
                poolCreator: ZERO_ADDRESS
            }),
            swapFeePercentage: DEFAULT_SWAP_FEE_PERCENTAGE,
            poolHooksContract: ZERO_ADDRESS,
            enableDonation: false,
            disableUnbalancedLiquidity: false,
            salt: ZERO_BYTES32
        });

        (IWeightedPool weightedPool, uint256[] memory removeExactAmountsIn, uint256 bptAmountOut) = _migrateLiquidity(
            weightedPoolParams
        );

        uint256[] memory weights = new uint256[](2);
        weights[projectIdx] = weightProjectToken;
        weights[reserveIdx] = weightReserveToken;

        // Check balances after migration
        uint256 _bptPercentageToMigrate = bptPercentageToMigrate;
        (
            uint256[] memory expectedLBPBalances,
            uint256[] memory expectedLBPBalancesScaled18
        ) = _calculateExpectedLBPBalances(
                lbpBalancesBeforeScaled18,
                ILBPool(pool).getLBPoolDynamicData().normalizedWeights,
                weights,
                [uint256(1), 1].toMemoryArray(),
                _bptPercentageToMigrate
            );

        _checkLBPAndWeightedPoolBalancesAfterMigration(
            weightedPool,
            bptAmountOut,
            lbpBalancesBeforeScaled18,
            removeExactAmountsIn,
            expectedLBPBalances,
            expectedLBPBalancesScaled18,
            [uint256(1), 1].toMemoryArray()
        );

        _checkPrice(weightedPool, lbpBalancesBeforeScaled18, weights);

        (IERC20[] memory weightedPoolTokens, TokenInfo[] memory weightedPoolTokenInfo, , ) = vault.getPoolTokenInfo(
            address(weightedPool)
        );

        // Check pool creation parameters
        {
            assertEq(IERC20Metadata(address(weightedPool)).name(), POOL_NAME, "Incorrect pool name");
            assertEq(IERC20Metadata(address(weightedPool)).symbol(), POOL_SYMBOL, "Incorrect pool symbol");

            assertEq(weightedPoolTokens.length, lbpTokens.length, "Token arrays length mismatch");
            assertEq(weightedPoolTokenInfo.length, lbpTokenInfo.length, "Token info arrays length mismatch");
            for (uint256 i = 0; i < weightedPoolTokenInfo.length; i++) {
                assertEq(address(weightedPoolTokens[i]), address(lbpTokens[i]), "Token address mismatch");

                assertEq(
                    uint256(weightedPoolTokenInfo[i].tokenType),
                    uint256(lbpTokenInfo[i].tokenType),
                    "Token type mismatch"
                );
                assertEq(
                    address(weightedPoolTokenInfo[i].rateProvider),
                    address(lbpTokenInfo[i].rateProvider),
                    "Rate provider address mismatch"
                );
                assertEq(
                    weightedPoolTokenInfo[i].paysYieldFees,
                    lbpTokenInfo[i].paysYieldFees,
                    "Pays yield fees mismatch"
                );
            }

            PoolConfig memory poolConfig = vault.getPoolConfig(address(weightedPool));
            assertEq(poolConfig.staticSwapFeePercentage, DEFAULT_SWAP_FEE_PERCENTAGE, "Incorrect swap fee percentage");
            assertEq(
                poolConfig.liquidityManagement.disableUnbalancedLiquidity,
                false,
                "Disable unbalanced liquidity should be false"
            );
            assertEq(poolConfig.liquidityManagement.enableDonation, false, "Enable donation should be false");

            assertEq(
                vault.getHooksConfig(address(weightedPool)).hooksContract,
                ZERO_ADDRESS,
                "Pool hooks contract should be zero address"
            );

            uint256[] memory currentWeights = weightedPool.getNormalizedWeights();
            assertEq(currentWeights.length, weights.length, "Incorrect number of weights");
            assertEq(currentWeights[projectIdx], weights[projectIdx], "Project token weight mismatch");
            assertEq(currentWeights[reserveIdx], weights[reserveIdx], "Reserve token weight mismatch");
        }
    }

    function testMigrationLiquidityRevertsIfMigrationNotSetup() external {
        PoolRoleAccounts memory poolRoleAccounts;

        (address poolWithoutMigration, ) = _createLBPool(
            address(0),
            uint32(block.timestamp + DEFAULT_START_OFFSET),
            uint32(block.timestamp + DEFAULT_END_OFFSET),
            DEFAULT_PROJECT_TOKENS_SWAP_IN
        );

        vm.startPrank(bob);
        _initPool(poolWithoutMigration, [poolInitAmount, poolInitAmount].toMemoryArray(), 0);
        vm.stopPrank();

        vm.expectRevert(
            abi.encodeWithSelector(ILBPMigrationRouter.IncorrectMigrationRouter.selector, ZERO_ADDRESS, migrationRouter)
        );
        vm.prank(bob);
        migrationRouter.migrateLiquidity(
            ILBPool(poolWithoutMigration),
            excessReceiver,
            ILBPMigrationRouter.WeightedPoolParams({
                name: POOL_NAME,
                symbol: POOL_SYMBOL,
                roleAccounts: poolRoleAccounts,
                swapFeePercentage: DEFAULT_SWAP_FEE_PERCENTAGE,
                poolHooksContract: ZERO_ADDRESS,
                enableDonation: true,
                disableUnbalancedLiquidity: true,
                salt: ZERO_BYTES32
            })
        );
    }

    function testMigrateLiquidityRevertsIfSenderIsNotPoolOwner() external {
        vm.warp(ILBPool(pool).getLBPoolImmutableData().endTime + 1);

        PoolRoleAccounts memory poolRoleAccounts;

        vm.expectRevert(ILBPMigrationRouter.SenderIsNotLBPOwner.selector);
        vm.prank(alice);
        migrationRouter.migrateLiquidity(
            ILBPool(pool),
            excessReceiver,
            ILBPMigrationRouter.WeightedPoolParams({
                name: POOL_NAME,
                symbol: POOL_SYMBOL,
                roleAccounts: poolRoleAccounts,
                swapFeePercentage: DEFAULT_SWAP_FEE_PERCENTAGE,
                poolHooksContract: ZERO_ADDRESS,
                enableDonation: true,
                disableUnbalancedLiquidity: true,
                salt: ZERO_BYTES32
            })
        );
    }

    function testMigrateLiquidityWithDecimalsRelatedPool() external {
        uint256 weightReserveToken = 50e16;
        uint256 weightProjectToken = 50e16;
        uint256 bptPercentageToMigrate = 50e16; // 50%

        projectToken = wbtc8Decimals;
        reserveToken = usdc6Decimals;
        (projectIdx, reserveIdx) = getSortedIndexes(address(projectToken), address(reserveToken));

        uint256[] memory decimalScalingFactors = new uint256[](2);
        decimalScalingFactors[projectIdx] = WBTC8_SCALING_FACTOR;
        decimalScalingFactors[reserveIdx] = USDC6_SCALING_FACTOR;

        (pool, ) = _createLBPoolWithMigration(
            address(0), // Pool creator
            DEFAULT_BPT_LOCK_DURATION,
            bptPercentageToMigrate,
            weightProjectToken,
            weightReserveToken
        );

        uint256[] memory initLBPAmounts = new uint256[](2);
        initLBPAmounts[projectIdx] = wbtc8DecimalsInitAmount;
        initLBPAmounts[reserveIdx] = usdc6DecimalsInitAmount;

        vm.startPrank(bob);
        _initPool(pool, initLBPAmounts, 0);

        uint256[] memory weights = new uint256[](2);
        weights[projectIdx] = weightProjectToken;
        weights[reserveIdx] = weightReserveToken;

        vm.warp(ILBPool(pool).getLBPoolImmutableData().endTime + 1);
        IERC20(pool).approve(address(migrationRouter), IERC20(pool).balanceOf(bob));

        (, , , uint256[] memory lbpBalancesBeforeScaled18) = vault.getPoolTokenInfo(pool);

        (IWeightedPool weightedPool, uint256[] memory removeExactAmountsIn, uint256 bptAmountOut) = migrationRouter
            .migrateLiquidity(
                ILBPool(pool),
                excessReceiver,
                ILBPMigrationRouter.WeightedPoolParams({
                    name: POOL_NAME,
                    symbol: POOL_SYMBOL,
                    roleAccounts: PoolRoleAccounts({
                        pauseManager: makeAddr("pauseManager"),
                        swapFeeManager: makeAddr("swapFeeManager"),
                        poolCreator: ZERO_ADDRESS
                    }),
                    swapFeePercentage: DEFAULT_SWAP_FEE_PERCENTAGE,
                    poolHooksContract: ZERO_ADDRESS,
                    enableDonation: false,
                    disableUnbalancedLiquidity: false,
                    salt: ZERO_BYTES32
                })
            );
        vm.stopPrank();

        (uint256 lbpPrice, uint256 weightedPoolPrice) = _checkPrice(weightedPool, lbpBalancesBeforeScaled18, weights);
        assertApproxEqRel(lbpPrice, 100_000e18, DELTA_REL, "LBP price should be 100,000");
        assertApproxEqRel(weightedPoolPrice, 100_000e18, DELTA_REL, "Weighted pool price should be 100,000");

        uint256 _bptPercentageToMigrate = bptPercentageToMigrate;
        (
            uint256[] memory expectedLBPBalancesAfter,
            uint256[] memory expectedLBPBalancesAfterScaled18
        ) = _calculateExpectedLBPBalances(
                lbpBalancesBeforeScaled18,
                ILBPool(pool).getLBPoolDynamicData().normalizedWeights,
                weights,
                decimalScalingFactors,
                _bptPercentageToMigrate
            );
        uint256[] memory _decimalScalingFactors = decimalScalingFactors;
        _checkLBPAndWeightedPoolBalancesAfterMigration(
            weightedPool,
            bptAmountOut,
            lbpBalancesBeforeScaled18,
            removeExactAmountsIn,
            expectedLBPBalancesAfter,
            expectedLBPBalancesAfterScaled18,
            _decimalScalingFactors
        );
    }

    function testMigrateSeedlessLiquidity_ProjectConstrained() external {
        // This tests the case where we have plenty of project tokens but limited real reserve
        // The migration uses all project tokens and calculates required reserve from spot price

        (pool, ) = _createSeedlessLBPoolWithMigration(
            80e16, // 80% project
            20e16, // 20% reserve
            poolInitAmount // Virtual reserve balance
        );

        // Initialize with only project tokens (seedless)
        uint256[] memory initAmounts = new uint256[](2);
        initAmounts[projectIdx] = poolInitAmount;
        initAmounts[reserveIdx] = 0;

        vm.startPrank(bob);
        _initPool(pool, initAmounts, 0);
        vm.stopPrank();

        // Do a swap to accumulate some real reserve (25% of virtual balance)
        uint256 swapAmount = poolInitAmount / 4; // virtual balance = poolInitAmount
        vm.warp(block.timestamp + DEFAULT_START_OFFSET + 1);

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

        // Warp to end of sale
        vm.warp(ILBPool(pool).getLBPoolImmutableData().endTime + 1);

        // Get balances before migration
        uint256[] memory lbpBalancesBeforeScaled18 = vault.getCurrentLiveBalances(pool);
        uint256 realReserveScaled18 = lbpBalancesBeforeScaled18[reserveIdx];

        uint256 spotPrice = IPoolInfo(pool).computeSpotPrice(reserveIdx);

        vm.startPrank(bob);
        IERC20(pool).approve(address(migrationRouter), IERC20(pool).balanceOf(bob));

        (IWeightedPool weightedPool, uint256[] memory exactAmountsIn, ) = migrationRouter.migrateLiquidity(
            ILBPool(pool),
            excessReceiver,
            ILBPMigrationRouter.WeightedPoolParams({
                name: POOL_NAME,
                symbol: POOL_SYMBOL,
                roleAccounts: PoolRoleAccounts({
                    pauseManager: ZERO_ADDRESS,
                    swapFeeManager: ZERO_ADDRESS,
                    poolCreator: ZERO_ADDRESS
                }),
                swapFeePercentage: DEFAULT_SWAP_FEE_PERCENTAGE,
                poolHooksContract: ZERO_ADDRESS,
                enableDonation: false,
                disableUnbalancedLiquidity: false,
                salt: ZERO_BYTES32
            })
        );
        vm.stopPrank();

        uint256[] memory weightedPoolBalances = vault.getCurrentLiveBalances(address(weightedPool));

        // Verify we used all project tokens (scaled by migration percentage)
        assertApproxEqRel(
            weightedPoolBalances[projectIdx],
            lbpBalancesBeforeScaled18[projectIdx].mulDown(SEEDLESS_BPT_SHARE_TO_MIGRATE),
            DELTA_REL,
            "Should use all project tokens"
        );

        // Verify reserve is less than what was available (we're project-constrained)
        assertLt(
            exactAmountsIn[reserveIdx],
            realReserveScaled18.mulDown(SEEDLESS_BPT_SHARE_TO_MIGRATE),
            "Should not use all reserve (project-constrained)"
        );

        // Verify spot price is preserved in weighted pool
        uint256 weightedPoolPrice = IPoolInfo(address(weightedPool)).computeSpotPrice(reserveIdx);

        assertApproxEqRel(weightedPoolPrice, spotPrice, DELTA_REL, "Spot price should be preserved after migration");
    }

    function testMigrateSeedlessLiquidity_ReserveConstrained() external {
        // This tests the case where the weighted pool weights require more reserve than available
        // The migration uses all real reserve and calculates project tokens from spot price

        (pool, ) = _createSeedlessLBPoolWithMigration(
            20e16, // 20% project (low weight means we need more reserve)
            80e16, // 80% reserve
            poolInitAmount // Virtual reserve balance
        );

        // Initialize with only project tokens (seedless)
        uint256[] memory initAmounts = new uint256[](2);
        initAmounts[projectIdx] = poolInitAmount;
        initAmounts[reserveIdx] = 0;

        vm.startPrank(bob);
        _initPool(pool, initAmounts, 0);
        vm.stopPrank();

        // Do a small swap to accumulate limited real reserve
        uint256 swapAmount = poolInitAmount / 10; // Only 10% of virtual balance (= pool init amount)
        vm.warp(block.timestamp + DEFAULT_START_OFFSET + 1);

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

        // Warp to end of sale
        vm.warp(ILBPool(pool).getLBPoolImmutableData().endTime + 1);

        // Get balances before migration
        uint256[] memory lbpBalancesBeforeScaled18 = vault.getCurrentLiveBalances(pool);
        uint256 realReserveScaled18 = lbpBalancesBeforeScaled18[reserveIdx];

        // Spot price using effective reserve
        uint256 spotPrice = IPoolInfo(pool).computeSpotPrice(reserveIdx);

        vm.startPrank(bob);
        IERC20(pool).approve(address(migrationRouter), IERC20(pool).balanceOf(bob));

        (IWeightedPool weightedPool, uint256[] memory exactAmountsIn, ) = migrationRouter.migrateLiquidity(
            ILBPool(pool),
            excessReceiver,
            ILBPMigrationRouter.WeightedPoolParams({
                name: POOL_NAME,
                symbol: POOL_SYMBOL,
                roleAccounts: PoolRoleAccounts({
                    pauseManager: ZERO_ADDRESS,
                    swapFeeManager: ZERO_ADDRESS,
                    poolCreator: ZERO_ADDRESS
                }),
                swapFeePercentage: DEFAULT_SWAP_FEE_PERCENTAGE,
                poolHooksContract: ZERO_ADDRESS,
                enableDonation: false,
                disableUnbalancedLiquidity: false,
                salt: ZERO_BYTES32
            })
        );
        vm.stopPrank();

        uint256[] memory weightedPoolBalances = vault.getCurrentLiveBalances(address(weightedPool));

        // Verify we used all real reserve (scaled by migration percentage)
        assertApproxEqRel(
            weightedPoolBalances[reserveIdx],
            realReserveScaled18.mulDown(SEEDLESS_BPT_SHARE_TO_MIGRATE),
            DELTA_REL,
            "Should use all real reserve"
        );

        // Verify project tokens is less than what was available (we're reserve-constrained)
        assertLt(
            exactAmountsIn[projectIdx],
            lbpBalancesBeforeScaled18[projectIdx].mulDown(SEEDLESS_BPT_SHARE_TO_MIGRATE),
            "Should not use all project tokens (reserve-constrained)"
        );

        // Verify spot price is preserved in weighted pool
        uint256 weightedPoolPrice = IPoolInfo(address(weightedPool)).computeSpotPrice(reserveIdx);

        assertApproxEqRel(weightedPoolPrice, spotPrice, DELTA_REL, "Spot price should be preserved after migration");

        // Verify excess project tokens went to excessReceiver
        uint256 excessProject = projectToken.balanceOf(excessReceiver);
        assertGt(excessProject, 0, "Excess receiver should have project tokens");
    }

    function _createSeedlessLBPoolWithMigration(
        uint256 migrationWeightProjectToken,
        uint256 migrationWeightReserveToken,
        uint256 virtualBalance
    ) internal returns (address newPool, bytes memory poolArgs) {
        (
            LBPCommonParams memory lbpCommonParams,
            MigrationParams memory migrationParams,
            LBPParams memory lbpParams,
            FactoryParams memory factoryParams
        ) = _createParams(migrationWeightProjectToken, migrationWeightReserveToken, virtualBalance);

        uint256 salt = _saltCounter++;
        newPool = lbPoolFactory.createWithMigration(
            lbpCommonParams,
            migrationParams,
            lbpParams,
            swapFee,
            bytes32(salt),
            address(0) // poolCreator
        );

        poolArgs = abi.encode(lbpCommonParams, migrationParams, lbpParams, vault, factoryParams);
    }

    function _createParams(
        uint256 migrationWeightProjectToken,
        uint256 migrationWeightReserveToken,
        uint256 virtualBalance
    )
        internal
        view
        returns (
            LBPCommonParams memory lbpCommonParams,
            MigrationParams memory migrationParams,
            LBPParams memory lbpParams,
            FactoryParams memory factoryParams
        )
    {
        lbpCommonParams = LBPCommonParams({
            name: "Seedless LBPool",
            symbol: "SLBP",
            owner: bob,
            projectToken: projectToken,
            reserveToken: reserveToken,
            startTime: uint32(block.timestamp + DEFAULT_START_OFFSET),
            endTime: uint32(block.timestamp + DEFAULT_END_OFFSET),
            blockProjectTokenSwapsIn: DEFAULT_PROJECT_TOKENS_SWAP_IN
        });

        migrationParams = MigrationParams({
            migrationRouter: address(migrationRouter),
            lockDurationAfterMigration: DEFAULT_BPT_LOCK_DURATION,
            bptPercentageToMigrate: SEEDLESS_BPT_SHARE_TO_MIGRATE,
            migrationWeightProjectToken: migrationWeightProjectToken,
            migrationWeightReserveToken: migrationWeightReserveToken
        });

        lbpParams = LBPParams({
            projectTokenStartWeight: startWeights[projectIdx],
            reserveTokenStartWeight: startWeights[reserveIdx],
            projectTokenEndWeight: endWeights[projectIdx],
            reserveTokenEndWeight: endWeights[reserveIdx],
            reserveTokenVirtualBalance: virtualBalance
        });

        factoryParams = FactoryParams({ vault: vault, trustedRouter: address(router), poolVersion: poolVersion });
    }

    function _migrateLiquidity(
        ILBPMigrationRouter.WeightedPoolParams memory weightedPoolParams
    ) internal returns (IWeightedPool weightedPool, uint256[] memory removeExactAmountsIn, uint256 bptAmountOut) {
        // Check event vs returned values first.
        uint256 snapshotId = vm.snapshotState();
        _prankStaticCall();
        (uint256[] memory expectedRemoveExactAmountsIn, uint256 expectedBptAmountOut) = migrationRouter
            .queryMigrateLiquidity(ILBPool(pool), bob, excessReceiver, weightedPoolParams);

        vm.revertToState(snapshotId);
        vm.startPrank(bob);

        (weightedPool, removeExactAmountsIn, bptAmountOut) = migrationRouter.migrateLiquidity(
            ILBPool(pool),
            excessReceiver,
            weightedPoolParams
        );

        for (uint256 i = 0; i < expectedRemoveExactAmountsIn.length; ++i) {
            assertEq(expectedRemoveExactAmountsIn[i], removeExactAmountsIn[i], "ExactAmountsIn mismatch from query");
        }
        assertEq(expectedBptAmountOut, bptAmountOut, "Expected BPT amount out mismatch from query");

        vm.stopPrank();
    }

    function _checkLBPAndWeightedPoolBalancesAfterMigration(
        IWeightedPool weightedPool,
        uint256 bptAmountOut,
        uint256[] memory lbpBalancesBeforeScaled18,
        uint256[] memory removeExactAmountsIn,
        uint256[] memory expectedLBPBalancesAfter,
        uint256[] memory expectedLBPBalancesAfterScaled18,
        uint256[] memory decimalScalingFactors
    ) internal view {
        // Check that the weighted pool balance is correct
        (
            IERC20[] memory tokens,
            ,
            uint256[] memory weightedPoolBalancesRaw,
            uint256[] memory weightedPoolBalancesScaled18
        ) = vault.getPoolTokenInfo(address(weightedPool));

        assertApproxEqRel(
            weightedPoolBalancesScaled18[projectIdx],
            expectedLBPBalancesAfterScaled18[projectIdx],
            DELTA_REL,
            "Live balance mismatch for project token"
        );
        assertApproxEqRel(
            weightedPoolBalancesScaled18[reserveIdx],
            expectedLBPBalancesAfterScaled18[reserveIdx],
            DELTA_REL,
            "Live balance mismatch for reserve token"
        );

        assertEq(removeExactAmountsIn.length, 2, "Incorrect returned remove exact amounts in length");
        assertEq(
            removeExactAmountsIn[projectIdx],
            weightedPoolBalancesRaw[projectIdx],
            "Project token balance mismatch in returned remove exact amounts in"
        );
        assertEq(
            removeExactAmountsIn[reserveIdx],
            weightedPoolBalancesRaw[reserveIdx],
            "Reserve token balance mismatch in returned remove exact amounts in"
        );
        assertApproxEqAbs(
            expectedLBPBalancesAfter[projectIdx],
            weightedPoolBalancesRaw[projectIdx],
            DELTA,
            "Project token raw balance mismatch"
        );
        assertApproxEqAbs(
            expectedLBPBalancesAfter[reserveIdx],
            weightedPoolBalancesRaw[reserveIdx],
            DELTA,
            "Reserve token raw balance mismatch"
        );

        // Check bob's balances
        assertEq(IERC20(pool).balanceOf(bob), 0, "Bob should not hold any LBP BPT after migration");
        assertGt(tokens[projectIdx].balanceOf(bob), 0, "Bob should have received project tokens after migration");
        assertGt(tokens[reserveIdx].balanceOf(bob), 0, "Bob should have received reserve tokens after migration");

        // Check migrationRouter balances
        assertEq(
            IERC20(address(weightedPool)).balanceOf(address(migrationRouter)),
            bptAmountOut,
            "Router should hold the correct amount of BPT after migration"
        );

        assertEq(
            migrationRouter.balanceOf(bob, migrationRouter.getId(address(weightedPool))),
            bptAmountOut,
            "Router should have correct locked BPT balance for bob"
        );
        assertEq(
            migrationRouter.getUnlockTimestamp(migrationRouter.getId(address(weightedPool))),
            block.timestamp + DEFAULT_BPT_LOCK_DURATION,
            "Router should have correct unlock timestamp for locked BPT"
        );

        assertEq(
            IERC20(pool).balanceOf(address(migrationRouter)),
            0,
            "Router should not hold any LBP BPT after migration"
        );
        assertEq(
            tokens[projectIdx].balanceOf(address(migrationRouter)),
            0,
            "Router should not hold any project tokens after migration"
        );
        assertEq(
            tokens[reserveIdx].balanceOf(address(migrationRouter)),
            0,
            "Router should not hold any reserve tokens after migration"
        );

        // Check excessReceiver balances
        assertApproxEqAbs(
            tokens[projectIdx].balanceOf(excessReceiver),
            (lbpBalancesBeforeScaled18[projectIdx] - expectedLBPBalancesAfterScaled18[projectIdx])
                .toRawUndoRateRoundDown(decimalScalingFactors[projectIdx], DEFAULT_RATE),
            DELTA,
            "excessReceiver should hold the correct amount of project tokens after migration"
        );
        assertApproxEqAbs(
            tokens[reserveIdx].balanceOf(excessReceiver),
            (lbpBalancesBeforeScaled18[reserveIdx] - expectedLBPBalancesAfterScaled18[reserveIdx])
                .toRawUndoRateRoundDown(decimalScalingFactors[reserveIdx], DEFAULT_RATE),
            DELTA,
            "excessReceiver should hold the correct amount of reserve tokens after migration"
        );
    }

    function _checkPrice(
        IWeightedPool weightedPool,
        uint256[] memory lbpBalancesBeforeScaled18,
        uint256[] memory weight
    ) internal view returns (uint256 lbpPrice, uint256 weightedPoolPrice) {
        uint256[] memory weightedPoolBalancesScaled18 = vault.getCurrentLiveBalances(address(weightedPool));
        // Price: project tokens in terms of reserve tokens.
        weightedPoolPrice = (weightedPoolBalancesScaled18[reserveIdx].mulDown(weight[projectIdx])).divDown(
            weightedPoolBalancesScaled18[projectIdx].mulDown(weight[reserveIdx])
        );

        uint256[] memory lbpWeights = new uint256[](2);
        lbpWeights[projectIdx] = ILBPool(pool).getLBPoolDynamicData().normalizedWeights[projectIdx];
        lbpWeights[reserveIdx] = ILBPool(pool).getLBPoolDynamicData().normalizedWeights[reserveIdx];

        // Price: project tokens in terms of reserve tokens.
        lbpPrice = (lbpBalancesBeforeScaled18[reserveIdx].mulDown(lbpWeights[projectIdx])).divDown(
            lbpBalancesBeforeScaled18[projectIdx].mulDown(lbpWeights[reserveIdx])
        );

        assertApproxEqRel(
            weightedPoolPrice,
            lbpPrice,
            DELTA_REL,
            "Price mismatch between LBP and Weighted Pool after migration"
        );
    }

    /// @dev The same logic as in `migrateLiquidityHook`, but uses b1 as the base calculation amount.
    /// The result should be almost the same; the only difference is in rounding.
    function _calculateExpectedLBPBalances(
        uint256[] memory balances,
        uint256[] memory weights,
        uint256[] memory newWeights,
        uint256[] memory decimalScalingFactors,
        uint256 bptPercentageToMigrate
    ) internal view returns (uint256[] memory expectedBalances, uint256[] memory expectedBalancesScaled18) {
        uint256 price = (balances[projectIdx].mulDown(weights[reserveIdx])).divDown(
            balances[reserveIdx].mulDown(weights[projectIdx])
        );

        uint256 projectAmountOut = price.mulDown(balances[reserveIdx]).mulDown(newWeights[projectIdx]).divDown(
            newWeights[reserveIdx]
        );
        uint256 reserveAmountOut = balances[reserveIdx] - 1;

        if (projectAmountOut > balances[projectIdx]) {
            projectAmountOut = balances[projectIdx] - 1;
            reserveAmountOut = (balances[projectIdx].mulDown(newWeights[reserveIdx])).divDown(
                price.mulDown(newWeights[projectIdx])
            );
        }

        // We convert to raw and then back to scaled18 to account for the actual rounding in vault conversions.
        expectedBalancesScaled18 = new uint256[](TOKEN_COUNT);
        expectedBalances = new uint256[](TOKEN_COUNT);
        expectedBalances[projectIdx] = projectAmountOut.mulDown(bptPercentageToMigrate).toRawUndoRateRoundDown(
            decimalScalingFactors[projectIdx],
            DEFAULT_RATE
        );
        expectedBalances[reserveIdx] = reserveAmountOut.mulDown(bptPercentageToMigrate).toRawUndoRateRoundDown(
            decimalScalingFactors[reserveIdx],
            DEFAULT_RATE
        );

        expectedBalancesScaled18[projectIdx] = expectedBalances[projectIdx].toScaled18ApplyRateRoundDown(
            decimalScalingFactors[projectIdx],
            DEFAULT_RATE
        );
        expectedBalancesScaled18[reserveIdx] = expectedBalances[reserveIdx].toScaled18ApplyRateRoundDown(
            decimalScalingFactors[reserveIdx],
            DEFAULT_RATE
        );
    }
}
