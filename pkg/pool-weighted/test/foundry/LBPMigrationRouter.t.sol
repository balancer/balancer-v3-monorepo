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
    uint256 constant DEFAULT_WEIGHT0 = 30e16; // 30% for project token
    uint256 constant DEFAULT_WEIGHT1 = 70e16; // 70% for reserve token

    string constant POOL_NAME = "Weighted Pool";
    string constant POOL_SYMBOL = "WP";
    string constant VERSION = "LBP Migration Router v1";

    address excessReceiver = makeAddr("excessReceiver");

    function testConstructorWithIncorrectWeightedPoolFactory() external {
        vm.prank(admin);
        balancerContractRegistry.deprecateBalancerContract(address(weightedPoolFactory));

        vm.expectRevert(
            abi.encodeWithSelector(ILBPMigrationRouter.ContractIsNotActiveInRegistry.selector, "WeightedPool")
        );
        new LBPMigrationRouter(balancerContractRegistry, VERSION);
    }

    function testLockAmount() external {
        uint256 amount = 101e18;
        uint256 duration = 1 days;
        address pool = address(new ERC20TestToken("Pool Token", "PT", 12));

        migrationRouter.manualLockAmount(IERC20(pool), alice, amount, duration);

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
        migrationRouter.manualLockAmount(IERC20(pool), alice, amount, duration);

        vm.warp(block.timestamp + duration);
        vm.prank(alice);
        migrationRouter.burn(address(pool));

        uint256 aliceWrappedTokenBalanceAfter = migrationRouter.balanceOf(alice, id);
        uint256 aliceTokenBalanceAfter = IERC20(pool).balanceOf(alice);
        uint256 routerTokenBalanceAfter = IERC20(pool).balanceOf(address(migrationRouter));

        assertEq(aliceWrappedTokenBalanceAfter, 0, "Alice's wrapped token balance after unlock is incorrect");
        assertEq(aliceTokenBalanceAfter, amount, "Alice's token balance after unlock is incorrect");
        assertEq(routerTokenBalanceAfter, 0, "Router's token balance after unlock is incorrect");
    }

    function testUnlockAmountRevertsIfAmountIsZero() external {
        vm.expectRevert(BPTTimeLocker.NoLockedAmount.selector);
        migrationRouter.burn(address(0));
    }

    function testUnlockAmountRevertsIfUnlockTimestampNotReached() external {
        ERC20TestToken pool = new ERC20TestToken("Pool Token", "PT", 12);
        uint256 unlockTimestamp = block.timestamp + DEFAULT_BPT_LOCK_DURATION;
        migrationRouter.manualLockAmount(pool, alice, 1e10, DEFAULT_BPT_LOCK_DURATION);

        vm.expectRevert(abi.encodePacked(BPTTimeLocker.AmountNotUnlockedYet.selector, unlockTimestamp));
        vm.prank(alice);
        migrationRouter.burn(address(pool));
    }

    function testMigrateLiquidityWithSpecificParameters() external {
        uint256 weight0 = 80e16;
        uint256 weight1 = 20e16;
        uint256 shareToMigrate = 50e16;

        (pool, ) = _createLBPoolWithMigration(DEFAULT_BPT_LOCK_DURATION, shareToMigrate, weight0, weight1);
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

        (IWeightedPool weightedPool, ) = migrationRouter.migrateLiquidity(
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

        uint256 price = (balances[0] * lbpWeights[1]).divDown(balances[1] * lbpWeights[0]);

        uint256 b0 = balances[0];
        uint256 b1 = (balances[0] * weight1).divDown(price * weight0);

        uint256[] memory expectedBalances = new uint256[](TOKEN_COUNT);
        expectedBalances[0] = b0.mulDown(shareToMigrate);
        expectedBalances[1] = b1.mulDown(shareToMigrate);

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

    function testMigrateLiquidity__Fuzz(uint256 weight0, uint256 shareToMigrate) external {
        weight0 = bound(weight0, 10e16, 90e16);
        uint256 weight1 = FixedPoint.ONE - weight0;
        shareToMigrate = bound(shareToMigrate, 10e16, 100e16);

        (pool, ) = _createLBPoolWithMigration(DEFAULT_BPT_LOCK_DURATION, shareToMigrate, weight0, weight1);
        initPool();

        vm.startPrank(bob);

        uint256[] memory weights = [weight0, weight1].toMemoryArray();

        vm.warp(ILBPool(pool).getLBPoolImmutableData().endTime + 1);

        uint256 lbpBPTBalanceBefore = IERC20(pool).balanceOf(bob);
        IERC20(pool).approve(address(migrationRouter), lbpBPTBalanceBefore);

        (IERC20[] memory lbpTokens, TokenInfo[] memory lbpTokenInfo, , uint256[] memory lbpBalancesBefore) = vault
            .getPoolTokenInfo(pool);

        PoolRoleAccounts memory poolRoleAccounts = PoolRoleAccounts({
            pauseManager: makeAddr("pauseManager"),
            swapFeeManager: makeAddr("swapFeeManager"),
            poolCreator: address(0)
        });

        (IWeightedPool weightedPool, uint256 bptAmountOut) = migrationRouter.migrateLiquidity(
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
                address(0),
                "Pool hooks contract should be zero address"
            );

            uint256[] memory currentWeights = weightedPool.getNormalizedWeights();
            assertEq(currentWeights.length, weights.length, "Incorrect number of weights");
            assertEq(currentWeights[projectIdx], weights[projectIdx], "Project token weight mismatch");
            assertEq(currentWeights[reserveIdx], weights[reserveIdx], "Reserve token weight mismatch");
        }

        // Check the liquidity migration result
        {
            uint256 _shareToMigrate = shareToMigrate;
            uint256[] memory lbpWeights = ILBPool(pool).getLBPoolDynamicData().normalizedWeights;
            uint256[] memory expectedBalances = _calculateExactAmountsIn(
                lbpWeights,
                lbpBalancesBefore,
                weights,
                _shareToMigrate
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

        vm.expectRevert(abi.encodeWithSelector(ILBPMigrationRouter.IncorrectMigrationRouter.selector, address(0)));
        vm.prank(bob);
        migrationRouter.migrateLiquidity(
            ILBPool(pool),
            excessReceiver,
            ILBPMigrationRouter.WeightedPoolParams({
                name: POOL_NAME,
                symbol: POOL_SYMBOL,
                roleAccounts: poolRoleAccounts,
                swapFeePercentage: DEFAULT_SWAP_FEE_PERCENTAGE,
                poolHooksContract: address(0),
                enableDonation: true,
                disableUnbalancedLiquidity: true,
                salt: bytes32(0)
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
                poolHooksContract: address(0),
                enableDonation: true,
                disableUnbalancedLiquidity: true,
                salt: bytes32(0)
            })
        );
    }

    /// @dev The same logic as in `migrateLiquidityHook`, but uses b1 as the base calculation amount.
    /// The result should be almost the same; the only difference is in rounding.
    function _calculateExactAmountsIn(
        uint256[] memory weights,
        uint256[] memory balances,
        uint256[] memory newWeights,
        uint256 shareToMigrate
    ) internal pure returns (uint256[] memory exactAmountsIn) {
        uint256 price = (balances[0] * weights[1]).divDown(balances[1] * weights[0]);

        uint256 b0 = price.mulDown(balances[1]).mulDown(newWeights[0]).divDown(newWeights[1]);
        uint256 b1 = balances[1];

        if (b0 > balances[0]) {
            b0 = balances[0];
            b1 = (balances[0] * newWeights[1]).divDown(price * newWeights[0]);
        }

        exactAmountsIn = new uint256[](TOKEN_COUNT);
        exactAmountsIn[0] = b0.mulDown(shareToMigrate);
        exactAmountsIn[1] = b1.mulDown(shareToMigrate);
    }
}
