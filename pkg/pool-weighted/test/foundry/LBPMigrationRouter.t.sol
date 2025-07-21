// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { ERC20TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC20TestToken.sol";

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

import { BaseLBPTest } from "./utils/BaseLBPTest.sol";
import { BPTTimeLocker } from "../../contracts/lbp/BPTTimeLocker.sol";

contract LBPMigrationRouterTest is BaseLBPTest {
    using ArrayHelpers for *;
    using FixedPoint for uint256;

    uint256 constant DELTA = 1e7;
    uint256 constant DEFAULT_BPT_LOCK_DURATION = 10 days;
    uint256 constant DEFAULT_SHARE_TO_MIGRATE = 70e16; // 70% of the pool
    uint256 constant DEFAULT_WEIGHT_PROJECT_TOKEN = 30e16; // 30% for project token
    uint256 constant DEFAULT_WEIGHT_RESERVE_TOKEN = 70e16; // 70% for reserve token

    string constant POOL_NAME = "Weighted Pool";
    string constant POOL_SYMBOL = "WP";
    string constant VERSION = "LBP Migration Router v1";

    address excessReceiver = makeAddr("excessReceiver");

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

        uint256 lbpBPTBalanceBefore = IERC20(pool).balanceOf(bob);
        IERC20(pool).approve(address(migrationRouter), lbpBPTBalanceBefore);

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

        uint256[] memory expectedBalances = new uint256[](TOKEN_COUNT);
        expectedBalances[projectIdx] = newBalanceProjectToken.mulDown(bptPercentageToMigrate);
        expectedBalances[reserveIdx] = newBalanceReserveToken.mulDown(bptPercentageToMigrate);

        // Check that the weighted pool balance is correct
        uint256[] memory balancesLiveScaled18 = vault.getCurrentLiveBalances(address(weightedPool));
        assertApproxEqAbs(
            balancesLiveScaled18[projectIdx],
            expectedBalances[projectIdx],
            DELTA,
            "Live balance mismatch for project token"
        );
        assertApproxEqAbs(
            balancesLiveScaled18[reserveIdx],
            expectedBalances[reserveIdx],
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

        (pool, ) = _createLBPoolWithMigration(
            address(0), // Pool creator
            DEFAULT_BPT_LOCK_DURATION,
            bptPercentageToMigrate,
            weightProjectToken,
            weightReserveToken
        );
        initPool();

        vm.startPrank(bob);

        uint256[] memory weights = [weightProjectToken, weightReserveToken].toMemoryArray();

        vm.warp(ILBPool(pool).getLBPoolImmutableData().endTime + 1);

        uint256 lbpBPTBalanceBefore = IERC20(pool).balanceOf(bob);
        IERC20(pool).approve(address(migrationRouter), lbpBPTBalanceBefore);

        (IERC20[] memory lbpTokens, TokenInfo[] memory lbpTokenInfo, , uint256[] memory lbpBalancesBefore) = vault
            .getPoolTokenInfo(pool);

        IWeightedPool weightedPool;
        uint256[] memory exactAmountsIn;
        uint256 bptAmountOut;
        {
            // Check event vs returned values first.
            uint256 snapshotId = vm.snapshotState();
            (weightedPool, exactAmountsIn, bptAmountOut) = migrationRouter.migrateLiquidity(
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

            vm.revertToState(snapshotId);
        }

        vm.expectEmit();
        emit ILBPMigrationRouter.PoolMigrated(ILBPool(pool), weightedPool, exactAmountsIn, bptAmountOut);

        (weightedPool, exactAmountsIn, bptAmountOut) = migrationRouter.migrateLiquidity(
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

        // Check the liquidity migration result
        {
            uint256 _bptPercentageToMigrate = bptPercentageToMigrate;
            uint256[] memory lbpWeights = ILBPool(pool).getLBPoolDynamicData().normalizedWeights;
            uint256[] memory expectedBalances = _calculateExactAmountsIn(
                lbpWeights,
                lbpBalancesBefore,
                weights,
                _bptPercentageToMigrate
            );

            // Check that the weighted pool balance is correct
            uint256[] memory balancesLiveScaled18 = vault.getCurrentLiveBalances(address(weightedPool));
            assertApproxEqAbs(
                balancesLiveScaled18[projectIdx],
                expectedBalances[projectIdx],
                DELTA,
                "Live balance mismatch for project token"
            );
            assertApproxEqAbs(
                balancesLiveScaled18[reserveIdx],
                expectedBalances[reserveIdx],
                DELTA,
                "Live balance mismatch for reserve token"
            );

            assertEq(exactAmountsIn.length, 2, "Incorrect returned exact amounts in length");
            assertEq(balancesLiveScaled18[projectIdx], exactAmountsIn[projectIdx], "Project token balance mismatch");
            assertEq(balancesLiveScaled18[reserveIdx], exactAmountsIn[reserveIdx], "Reserve token balance mismatch");

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
                lbpBalancesBefore[projectIdx] - expectedBalances[projectIdx],
                DELTA,
                "excessReceiver should hold the correct amount of project tokens after migration"
            );
            assertApproxEqAbs(
                tokens[reserveIdx].balanceOf(excessReceiver),
                lbpBalancesBefore[reserveIdx] - expectedBalances[reserveIdx],
                DELTA,
                "excessReceiver should hold the correct amount of reserve tokens after migration"
            );
        }
    }

    function testMigrationLiquidityRevertsIfMigrationNotSetup() external {
        PoolRoleAccounts memory poolRoleAccounts;

        vm.expectRevert(
            abi.encodeWithSelector(ILBPMigrationRouter.IncorrectMigrationRouter.selector, ZERO_ADDRESS, migrationRouter)
        );
        vm.prank(bob);
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

    /// @dev The same logic as in `migrateLiquidityHook`, but uses b1 as the base calculation amount.
    /// The result should be almost the same; the only difference is in rounding.
    function _calculateExactAmountsIn(
        uint256[] memory weights,
        uint256[] memory balances,
        uint256[] memory newWeights,
        uint256 bptPercentageToMigrate
    ) internal view returns (uint256[] memory exactAmountsIn) {
        uint256 price = (balances[projectIdx] * weights[reserveIdx]).divDown(
            balances[reserveIdx] * weights[projectIdx]
        );

        uint256 projectAmountOut = price.mulDown(balances[reserveIdx]).mulDown(newWeights[projectIdx]).divDown(
            newWeights[reserveIdx]
        );
        uint256 reserveAmountOut = balances[reserveIdx];

        if (projectAmountOut > balances[projectIdx]) {
            projectAmountOut = balances[projectIdx];
            reserveAmountOut = (balances[projectIdx] * newWeights[reserveIdx]).divDown(price * newWeights[projectIdx]);
        }

        exactAmountsIn = new uint256[](TOKEN_COUNT);
        exactAmountsIn[projectIdx] = projectAmountOut.mulDown(bptPercentageToMigrate);
        exactAmountsIn[reserveIdx] = reserveAmountOut.mulDown(bptPercentageToMigrate);
    }
}
