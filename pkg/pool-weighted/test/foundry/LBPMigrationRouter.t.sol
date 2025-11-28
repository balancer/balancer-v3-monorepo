// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/console.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { ERC20TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC20TestToken.sol";
import { ScalingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ScalingHelpers.sol";

import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { ILBPool } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPool.sol";
import { IWeightedPool } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/IWeightedPool.sol";
import { ILBPMigrationRouter } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPMigrationRouter.sol";
import { ContractType } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IBalancerContractRegistry.sol";
import {
    PoolConfig,
    TokenConfig,
    TokenInfo,
    TokenType,
    PoolRoleAccounts
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { LBPMigrationRouter } from "../../contracts/lbp/LBPMigrationRouter.sol";
import { WeightedPoolFactory } from "../../contracts/WeightedPoolFactory.sol";
import { LBPMigrationRouterMock } from "../../contracts/test/LBPMigrationRouterMock.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { BalancerContractRegistry } from "@balancer-labs/v3-standalone-utils/contracts/BalancerContractRegistry.sol";

import { BPTTimeLocker } from "../../contracts/lbp/BPTTimeLocker.sol";
import { WeightedLBPTest } from "./utils/WeightedLBPTest.sol";

contract LBPMigrationRouterTest is WeightedLBPTest {
    using ArrayHelpers for *;
    using FixedPoint for uint256;
    using ScalingHelpers for uint256;

    uint256 constant USDC6_SCALING_FACTOR = 1e12;
    uint256 constant WBTC8_SCALING_FACTOR = 1e10;
    uint256 constant DEFAULT_RATE = 1e18;
    uint256 constant DELTA = 1e7;
    uint256 internal constant DEFAULT_BPT_LOCK_DURATION = 10 days;
    uint256 internal constant DEFAULT_SHARE_TO_MIGRATE = 70e16; // 70% of the pool
    uint256 internal constant DEFAULT_WEIGHT_PROJECT_TOKEN = 30e16; // 30% for project token
    uint256 internal constant DEFAULT_WEIGHT_RESERVE_TOKEN = 70e16; // 70% for reserve token

    string constant POOL_NAME = "Weighted Pool";
    string constant POOL_SYMBOL = "WP";
    string constant VERSION = "LBP Migration Router v1";

    address excessReceiver = makeAddr("excessReceiver");

    uint256 usdc6DecimalsInitAmount = 10_000e6;
    uint256 wbtc8DecimalsInitAmount = 1_000e8;

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

        (, , , uint256[] memory balances) = vault.getPoolTokenInfo(pool);

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
        uint256 newBalanceProjectToken = balances[projectIdx];
        // Project token balance represents 30% of the TVL of the LBP, and reserve token balance represents 70%.
        // In the new pool, project token balance represents 80% of the TVL, and reserve token balance represents 20%.
        // Then, 3/10 * TVL1 = 8/10 * TVL2, where TVL1 is the LBP TVL and TVL2 is the new pool TVL.
        // On the other hand, balance[reserve] = 7/10 * TVL1, and newBalance[reserve] = 2/10 * TVL2.
        // Solving for newBalance[reserve], we get:
        // newBalance[reserve] =
        //                 balance[reserve] * newWeightReserve / newWeightProject * oldWeightProject / oldWeightReserve

        uint256 newBalanceReserveToken = balances[reserveIdx]
            .mulDown(weightReserveToken)
            .divDown(weightProjectToken)
            .mulDown(lbpWeights[projectIdx])
            .divDown(lbpWeights[reserveIdx]);

        uint256[] memory expectedBalancesScaled18 = new uint256[](TOKEN_COUNT);
        expectedBalancesScaled18[projectIdx] = newBalanceProjectToken.mulDown(bptPercentageToMigrate);
        expectedBalancesScaled18[reserveIdx] = newBalanceReserveToken.mulDown(bptPercentageToMigrate);

        // Check that the weighted pool balance is correct
        uint256[] memory balancesLiveScaled18 = vault.getCurrentLiveBalances(address(weightedPool));
        assertApproxEqAbs(
            balancesLiveScaled18[projectIdx],
            expectedBalancesScaled18[projectIdx],
            DELTA,
            "Live balance mismatch for project token"
        );
        assertApproxEqAbs(
            balancesLiveScaled18[reserveIdx],
            expectedBalancesScaled18[reserveIdx],
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

        uint256[] memory weights = [weightProjectToken, weightReserveToken].toMemoryArray();

        // Check balances after migration
        uint256 _bptPercentageToMigrate = bptPercentageToMigrate;
        (uint256[] memory expectedBalances, uint256[] memory expectedBalancesScaled18) = _calculateExpectedBalances(
            lbpBalancesBeforeScaled18,
            ILBPool(pool).getLBPoolDynamicData().normalizedWeights,
            weights,
            [uint256(1), 1].toMemoryArray(),
            _bptPercentageToMigrate
        );

        _checkBalancesAfterMigration(
            weightedPool,
            bptAmountOut,
            lbpBalancesBeforeScaled18,
            removeExactAmountsIn,
            expectedBalances,
            expectedBalancesScaled18,
            [uint256(1), 1].toMemoryArray()
        );

        (IERC20[] memory tokens, TokenInfo[] memory tokenInfo, , ) = vault.getPoolTokenInfo(address(weightedPool));

        // Check pool creation parameters
        {
            assertEq(IERC20Metadata(address(weightedPool)).name(), POOL_NAME, "Incorrect pool name");
            assertEq(IERC20Metadata(address(weightedPool)).symbol(), POOL_SYMBOL, "Incorrect pool symbol");

            assertEq(tokens.length, lbpTokens.length, "Token arrays length mismatch");
            assertEq(tokenInfo.length, lbpTokenInfo.length, "Token info arrays length mismatch");
            for (uint256 i = 0; i < tokenInfo.length; i++) {
                assertEq(address(tokens[i]), address(lbpTokens[i]), "Token address mismatch");

                assertEq(uint256(tokenInfo[i].tokenType), uint256(lbpTokenInfo[i].tokenType), "Token type mismatch");
                assertEq(
                    address(tokenInfo[i].rateProvider),
                    address(lbpTokenInfo[i].rateProvider),
                    "Rate provider address mismatch"
                );
                assertEq(tokenInfo[i].paysYieldFees, lbpTokenInfo[i].paysYieldFees, "Pays yield fees mismatch");
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
        uint256 weightReserveToken = 70e16;
        uint256 weightProjectToken = 30e16;
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

        uint256[] memory initAmounts = new uint256[](2);
        initAmounts[projectIdx] = wbtc8DecimalsInitAmount;
        initAmounts[reserveIdx] = usdc6DecimalsInitAmount;

        vm.startPrank(bob);
        _initPool(pool, initAmounts, 0);

        uint256[] memory weights = [weightProjectToken, weightReserveToken].toMemoryArray();

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

        uint256 _bptPercentageToMigrate = bptPercentageToMigrate;
        (uint256[] memory expectedBalances, uint256[] memory expectedBalancesScaled18) = _calculateExpectedBalances(
            lbpBalancesBeforeScaled18,
            ILBPool(pool).getLBPoolDynamicData().normalizedWeights,
            weights,
            decimalScalingFactors,
            _bptPercentageToMigrate
        );
        uint256[] memory _decimalScalingFactors = decimalScalingFactors;
        _checkBalancesAfterMigration(
            weightedPool,
            bptAmountOut,
            lbpBalancesBeforeScaled18,
            removeExactAmountsIn,
            expectedBalances,
            expectedBalancesScaled18,
            _decimalScalingFactors
        );
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

    function _checkBalancesAfterMigration(
        IWeightedPool weightedPool,
        uint256 bptAmountOut,
        uint256[] memory lbpBalancesBeforeScaled18,
        uint256[] memory removeExactAmountsIn,
        uint256[] memory expectedBalances,
        uint256[] memory expectedBalancesScaled18,
        uint256[] memory decimalScalingFactors
    ) internal view {
        // Check that the weighted pool balance is correct
        (IERC20[] memory tokens, , uint256[] memory balancesRaw, uint256[] memory balancesLiveScaled18) = vault
            .getPoolTokenInfo(address(weightedPool));

        assertApproxEqAbs(
            balancesLiveScaled18[projectIdx],
            expectedBalancesScaled18[projectIdx],
            DELTA,
            "Live balance mismatch for project token"
        );
        assertApproxEqAbs(
            balancesLiveScaled18[reserveIdx],
            expectedBalancesScaled18[reserveIdx],
            DELTA,
            "Live balance mismatch for reserve token"
        );

        assertEq(removeExactAmountsIn.length, 2, "Incorrect returned remove exact amounts in length");
        assertEq(
            removeExactAmountsIn[projectIdx],
            balancesRaw[projectIdx],
            "Project token balance mismatch in returned remove exact amounts in"
        );
        assertEq(
            removeExactAmountsIn[reserveIdx],
            balancesRaw[reserveIdx],
            "Reserve token balance mismatch in returned remove exact amounts in"
        );
        assertApproxEqAbs(
            expectedBalances[projectIdx],
            balancesRaw[projectIdx],
            DELTA,
            "Project token raw balance mismatch"
        );
        assertApproxEqAbs(
            expectedBalances[reserveIdx],
            balancesRaw[reserveIdx],
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
            (lbpBalancesBeforeScaled18[projectIdx] - expectedBalancesScaled18[projectIdx]).toRawUndoRateRoundDown(
                decimalScalingFactors[projectIdx],
                DEFAULT_RATE
            ),
            DELTA,
            "excessReceiver should hold the correct amount of project tokens after migration"
        );
        assertApproxEqAbs(
            tokens[reserveIdx].balanceOf(excessReceiver),
            (lbpBalancesBeforeScaled18[reserveIdx] - expectedBalancesScaled18[reserveIdx]).toRawUndoRateRoundDown(
                decimalScalingFactors[reserveIdx],
                DEFAULT_RATE
            ),
            DELTA,
            "excessReceiver should hold the correct amount of reserve tokens after migration"
        );
    }

    /// @dev The same logic as in `migrateLiquidityHook`, but uses b1 as the base calculation amount.
    /// The result should be almost the same; the only difference is in rounding.
    function _calculateExpectedBalances(
        uint256[] memory balances,
        uint256[] memory weights,
        uint256[] memory newWeights,
        uint256[] memory decimalScalingFactors,
        uint256 bptPercentageToMigrate
    ) internal view returns (uint256[] memory expectedBalances, uint256[] memory expectedBalancesScaled18) {
        uint256 price = (balances[projectIdx] * weights[reserveIdx]).divDown(
            balances[reserveIdx] * weights[projectIdx]
        );

        uint256 projectAmountOut = price.mulDown(balances[reserveIdx]).mulDown(newWeights[projectIdx]).divDown(
            newWeights[reserveIdx]
        );
        uint256 reserveAmountOut = balances[reserveIdx] - 1;

        console.log("projectAmountOut > balances[projectIdx]: ", projectAmountOut > balances[projectIdx]);
        if (projectAmountOut > balances[projectIdx]) {
            projectAmountOut = balances[projectIdx] - 1;
            reserveAmountOut = (balances[projectIdx].mulDown(newWeights[reserveIdx])).divDown(
                price.mulDown(newWeights[projectIdx])
            );
        }

        console.log("projectAmountOut: ", projectAmountOut.mulDown(bptPercentageToMigrate));
        console.log("reserveAmountOut: ", reserveAmountOut.mulDown(bptPercentageToMigrate));

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

        console.log("Expected project token balance (raw): ", expectedBalances[projectIdx]);
        console.log("Expected reserve token balance (raw): ", expectedBalances[reserveIdx]);

        expectedBalancesScaled18[projectIdx] = expectedBalances[projectIdx].toScaled18ApplyRateRoundDown(
            decimalScalingFactors[projectIdx],
            DEFAULT_RATE
        );
        expectedBalancesScaled18[reserveIdx] = expectedBalances[reserveIdx].toScaled18ApplyRateRoundDown(
            decimalScalingFactors[reserveIdx],
            DEFAULT_RATE
        );

        console.log("Expected project token balance (scaled18): ", expectedBalancesScaled18[projectIdx]);
        console.log("Expected reserve token balance (scaled18): ", expectedBalancesScaled18[reserveIdx]);
    }
}
