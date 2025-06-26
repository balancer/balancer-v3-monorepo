// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

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
import { WeightedPoolContractsDeployer } from "./utils/WeightedPoolContractsDeployer.sol";

contract LBPMigrationRouterTest is BaseLBPTest, WeightedPoolContractsDeployer {
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

    WeightedPoolFactory weightedPoolFactory;
    BalancerContractRegistry balancerContractRegistry;
    LBPMigrationRouterMock lbpMigrationRouter;
    address excessReceiver = makeAddr("excessReceiver");

    function setUp() public override {
        super.setUp();

        weightedPoolFactory = deployWeightedPoolFactory(
            IVault(address(vault)),
            365 days,
            "Weighted Factory v1",
            "Weighted Pool v1"
        );

        balancerContractRegistry = new BalancerContractRegistry(IVault(address(vault)));
        authorizer.grantRole(
            balancerContractRegistry.getActionId(BalancerContractRegistry.registerBalancerContract.selector),
            admin
        );
        authorizer.grantRole(
            balancerContractRegistry.getActionId(BalancerContractRegistry.deprecateBalancerContract.selector),
            admin
        );

        vm.prank(admin);
        balancerContractRegistry.registerBalancerContract(
            ContractType.POOL_FACTORY,
            "WeightedPool",
            address(weightedPoolFactory)
        );

        lbpMigrationRouter = new LBPMigrationRouterMock(balancerContractRegistry, VERSION);
    }

    function testConstructorWithIncorrectWeightedPoolFactory() external {
        vm.prank(admin);
        balancerContractRegistry.deprecateBalancerContract(address(weightedPoolFactory));

        vm.expectRevert(
            abi.encodeWithSelector(ILBPMigrationRouter.ContractIsNotActiveInRegistry.selector, "WeightedPool")
        );
        new LBPMigrationRouter(balancerContractRegistry, VERSION);
    }

    function testSetupMigration() external {
        assertEq(lbpMigrationRouter.isMigrationSetup(ILBPool(pool)), false, "Migration should not be marked as setup");

        vm.prank(bob);
        vm.expectEmit();
        emit ILBPMigrationRouter.MigrationSetup(
            ILBPool(pool),
            DEFAULT_BPT_LOCK_DURATION,
            DEFAULT_SHARE_TO_MIGRATE,
            DEFAULT_WEIGHT0,
            DEFAULT_WEIGHT1
        );
        lbpMigrationRouter.setupMigration(
            ILBPool(pool),
            DEFAULT_BPT_LOCK_DURATION,
            DEFAULT_SHARE_TO_MIGRATE,
            DEFAULT_WEIGHT0,
            DEFAULT_WEIGHT1
        );

        LBPMigrationRouter.MigrationParams memory migrationParams = lbpMigrationRouter.getMigrationParams(
            ILBPool(pool)
        );
        assertEq(migrationParams.weight0, DEFAULT_WEIGHT0, "Weight0 mismatch in migration params");
        assertEq(migrationParams.weight1, DEFAULT_WEIGHT1, "Weight1 mismatch in migration params");
        assertEq(
            migrationParams.bptLockDuration,
            DEFAULT_BPT_LOCK_DURATION,
            "BPT lock duration mismatch in migration params"
        );
        assertEq(
            migrationParams.shareToMigrate,
            DEFAULT_SHARE_TO_MIGRATE,
            "Share to migrate mismatch in migration params"
        );

        assertEq(lbpMigrationRouter.isMigrationSetup(ILBPool(pool)), true, "Migration should be marked as setup");
    }

    function testSetupMigrationRevertsIfSenderIsNotPoolOwner() external {
        vm.expectRevert(ILBPMigrationRouter.SenderIsNotLBPOwner.selector);
        vm.prank(alice);
        lbpMigrationRouter.setupMigration(
            ILBPool(pool),
            DEFAULT_BPT_LOCK_DURATION,
            DEFAULT_SHARE_TO_MIGRATE,
            DEFAULT_WEIGHT0,
            DEFAULT_WEIGHT1
        );
    }

    function testSetupMigrationRevertsIfMigrationAlreadySetup() external {
        vm.prank(bob);
        lbpMigrationRouter.setupMigration(
            ILBPool(pool),
            DEFAULT_BPT_LOCK_DURATION,
            DEFAULT_SHARE_TO_MIGRATE,
            DEFAULT_WEIGHT0,
            DEFAULT_WEIGHT1
        );

        vm.expectRevert(ILBPMigrationRouter.MigrationAlreadySetup.selector);
        vm.prank(bob);
        lbpMigrationRouter.setupMigration(
            ILBPool(pool),
            DEFAULT_BPT_LOCK_DURATION,
            DEFAULT_SHARE_TO_MIGRATE,
            DEFAULT_WEIGHT0,
            DEFAULT_WEIGHT1
        );
    }

    function testSetupMigrationRevertsIfPoolIsNotRegistered() external {
        vault.manualSetPoolRegistered(pool, false);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(ILBPMigrationRouter.PoolNotRegistered.selector));
        lbpMigrationRouter.setupMigration(
            ILBPool(pool),
            DEFAULT_BPT_LOCK_DURATION,
            DEFAULT_SHARE_TO_MIGRATE,
            DEFAULT_WEIGHT0,
            DEFAULT_WEIGHT1
        );
    }

    function testSetupMigrationRevertsIfLBPAlreadyStarted() external {
        uint256 startTime = ILBPool(pool).getLBPoolImmutableData().startTime;
        vm.warp(startTime);

        vm.expectRevert(abi.encodeWithSelector(ILBPMigrationRouter.LBPAlreadyStarted.selector, startTime));
        vm.prank(bob);
        lbpMigrationRouter.setupMigration(
            ILBPool(pool),
            DEFAULT_BPT_LOCK_DURATION,
            DEFAULT_SHARE_TO_MIGRATE,
            DEFAULT_WEIGHT0,
            DEFAULT_WEIGHT1
        );
    }

    function testSetupMigrationRevertsIfWeightsAreZero() external {
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(ILBPMigrationRouter.InvalidMigrationWeights.selector));
        lbpMigrationRouter.setupMigration(
            ILBPool(pool),
            DEFAULT_BPT_LOCK_DURATION,
            DEFAULT_SHARE_TO_MIGRATE,
            0,
            FixedPoint.ONE
        );

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(ILBPMigrationRouter.InvalidMigrationWeights.selector));
        lbpMigrationRouter.setupMigration(
            ILBPool(pool),
            DEFAULT_BPT_LOCK_DURATION,
            DEFAULT_SHARE_TO_MIGRATE,
            FixedPoint.ONE,
            0
        );
    }

    function testSetupMigrationRevertsIfWeightsAreNotNormalized() external {
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(ILBPMigrationRouter.InvalidMigrationWeights.selector));
        lbpMigrationRouter.setupMigration(
            ILBPool(pool),
            DEFAULT_BPT_LOCK_DURATION,
            DEFAULT_SHARE_TO_MIGRATE,
            95e16,
            3e16
        );
    }

    function testLockAmount() external {
        uint256[] memory amounts = [100e18, 12000e18, uint256(1e17)].toMemoryArray();
        uint256[] memory durations = [1 days, 3 days, uint256(2 days)].toMemoryArray();

        address pool1 = makeAddr("pool1");
        address pool2 = makeAddr("pool2");

        address[] memory pools = [pool1, pool2, pool1].toMemoryArray();

        _testLockAmount(bob, amounts, durations, pools);
    }

    function testUnlockAmount() external {
        ERC20TestToken pool1 = new ERC20TestToken("Pool Token 1", "PT1", 18);
        ERC20TestToken pool2 = new ERC20TestToken("Pool Token 2", "PT2", 18);

        address[] memory pools = [address(pool1), address(pool2), address(pool1)].toMemoryArray();
        uint256[] memory amounts = [100e18, 12000e18, uint256(1e17)].toMemoryArray();
        uint256[] memory durations = [1 days, 3 days, uint256(2 days)].toMemoryArray();

        pool1.mint(address(lbpMigrationRouter), amounts[0] + amounts[2]);
        pool2.mint(address(lbpMigrationRouter), amounts[1]);

        _testLockAmount(bob, amounts, durations, pools);

        vm.warp(block.timestamp + 1 days);

        vm.prank(bob);
        lbpMigrationRouter.unlockTokens([uint256(0)].toMemoryArray());

        vm.warp(block.timestamp + 3 days);

        vm.prank(bob);
        lbpMigrationRouter.unlockTokens([uint256(1), uint256(2)].toMemoryArray());
    }

    function testUnlockAmountRevertsIfAmountIsZero() external {
        lbpMigrationRouter.manualAddLockedAmount(bob, makeAddr("pool"), 0, block.timestamp + DEFAULT_BPT_LOCK_DURATION);

        vm.expectRevert(abi.encodeWithSelector(ILBPMigrationRouter.TimeLockedAmountNotFound.selector, 0));
        vm.prank(bob);
        lbpMigrationRouter.unlockTokens([uint256(0)].toMemoryArray());
    }

    function testUnlockAmountRevertsIfUnlockTimestampNotReached() external {
        uint256 unlockTimestamp = block.timestamp + DEFAULT_BPT_LOCK_DURATION;
        lbpMigrationRouter.manualAddLockedAmount(bob, makeAddr("pool"), 100e18, unlockTimestamp);

        vm.expectRevert(
            abi.encodeWithSelector(ILBPMigrationRouter.TimeLockedAmountNotUnlockedYet.selector, 0, unlockTimestamp)
        );
        vm.prank(bob);
        lbpMigrationRouter.unlockTokens([uint256(0)].toMemoryArray());
    }

    function testMigrateLiquidityWithSpecificParameters() external {
        uint256 weight0 = 80e16;
        uint256 weight1 = 20e16;
        uint256 shareToMigrate = 50e16;

        vm.startPrank(bob);

        lbpMigrationRouter.setupMigration(ILBPool(pool), DEFAULT_BPT_LOCK_DURATION, shareToMigrate, weight0, weight1);

        vm.warp(ILBPool(pool).getLBPoolImmutableData().endTime + 1);

        uint256 lbpBPTBalanceBefore = IERC20(pool).balanceOf(bob);
        IERC20(pool).approve(address(lbpMigrationRouter), lbpBPTBalanceBefore);

        PoolRoleAccounts memory poolRoleAccounts = PoolRoleAccounts({
            pauseManager: makeAddr("pauseManager"),
            swapFeeManager: makeAddr("swapFeeManager"),
            poolCreator: address(0)
        });

        (, , , uint256[] memory balances) = vault.getPoolTokenInfo(pool);

        (IWeightedPool weightedPool, ) = lbpMigrationRouter.migrateLiquidity(
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

        vm.startPrank(bob);

        uint256[] memory weights = [weight0, weight1].toMemoryArray();
        lbpMigrationRouter.setupMigration(ILBPool(pool), DEFAULT_BPT_LOCK_DURATION, shareToMigrate, weight0, weight1);

        vm.warp(ILBPool(pool).getLBPoolImmutableData().endTime + 1);

        uint256 lbpBPTBalanceBefore = IERC20(pool).balanceOf(bob);
        IERC20(pool).approve(address(lbpMigrationRouter), lbpBPTBalanceBefore);

        (IERC20[] memory lbpTokens, TokenInfo[] memory lbpTokenInfo, , uint256[] memory lbpBalancesBefore) = vault
            .getPoolTokenInfo(pool);

        PoolRoleAccounts memory poolRoleAccounts = PoolRoleAccounts({
            pauseManager: makeAddr("pauseManager"),
            swapFeeManager: makeAddr("swapFeeManager"),
            poolCreator: address(0)
        });

        (IWeightedPool weightedPool, uint256 bptAmountOut) = lbpMigrationRouter.migrateLiquidity(
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

            // Check lbpMigrationRouter balances
            assertEq(
                IERC20(address(weightedPool)).balanceOf(address(lbpMigrationRouter)),
                bptAmountOut,
                "Router should hold the correct amount of BPT after migration"
            );

            ILBPMigrationRouter.TimeLockedAmount memory timeLockedAmount = lbpMigrationRouter.getTimeLockedAmount(
                bob,
                0
            );
            uint256 count = lbpMigrationRouter.getTimeLockedAmountsCount(bob);

            assertEq(count, 1, "Router should have one locked BPT for bob after migration");
            assertEq(timeLockedAmount.amount, bptAmountOut, "Router should have correct locked BPT amount");
            assertEq(
                timeLockedAmount.unlockTimestamp,
                block.timestamp + DEFAULT_BPT_LOCK_DURATION,
                "Router should have correct unlock timestamp for locked BPT"
            );
            assertEq(
                timeLockedAmount.token,
                address(weightedPool),
                "Router should have locked BPT for the correct pool"
            );

            assertEq(
                IERC20(pool).balanceOf(address(lbpMigrationRouter)),
                0,
                "Router should not hold any LBP BPT after migration"
            );
            assertEq(
                tokens[projectIdx].balanceOf(address(lbpMigrationRouter)),
                0,
                "Router should not hold any project tokens after migration"
            );
            assertEq(
                tokens[reserveIdx].balanceOf(address(lbpMigrationRouter)),
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

    function testMigrateLiquidityRevertsIfLBPWeightsNotFinalized() external {
        PoolRoleAccounts memory poolRoleAccounts;

        vm.prank(bob);
        lbpMigrationRouter.setupMigration(
            ILBPool(pool),
            DEFAULT_BPT_LOCK_DURATION,
            DEFAULT_SHARE_TO_MIGRATE,
            DEFAULT_WEIGHT0,
            DEFAULT_WEIGHT1
        );

        vm.expectRevert(abi.encodeWithSelector(ILBPMigrationRouter.LBPWeightsNotFinalized.selector, pool));
        vm.prank(bob);
        lbpMigrationRouter.migrateLiquidity(
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

    function testMigrationLiquidityRevertsIfMigrationNotSetup() external {
        PoolRoleAccounts memory poolRoleAccounts;

        vm.expectRevert(ILBPMigrationRouter.MigrationDoesNotExist.selector);
        vm.prank(bob);
        lbpMigrationRouter.migrateLiquidity(
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
        lbpMigrationRouter.migrateLiquidity(
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

    function _testLockAmount(
        address sender,
        uint256[] memory amounts,
        uint256[] memory durations,
        address[] memory pools
    ) internal {
        for (uint256 i = 0; i < amounts.length; i++) {
            ILBPMigrationRouter.MigrationHookParams memory hookParams;

            hookParams.sender = sender;
            hookParams.weightedPool = IWeightedPool(pools[i]);
            hookParams.migrationParams.bptLockDuration = uint64(durations[i]);

            vm.expectEmit();
            emit ILBPMigrationRouter.AmountLocked(sender, pools[i], amounts[i], block.timestamp + durations[i]);
            lbpMigrationRouter.manualLockAmount(hookParams, amounts[i]);

            ILBPMigrationRouter.TimeLockedAmount memory timeLockedAmount = lbpMigrationRouter.getTimeLockedAmount(
                sender,
                i
            );
            uint256 count = lbpMigrationRouter.getTimeLockedAmountsCount(sender);

            assertEq(count, i + 1, "Incorrect time locked amounts count");
            assertEq(timeLockedAmount.amount, amounts[i], "Incorrect time locked amount");
            assertEq(
                timeLockedAmount.unlockTimestamp,
                block.timestamp + durations[i],
                "Incorrect unlock timestamp for time locked amount"
            );
            assertEq(timeLockedAmount.token, address(pools[i]), "Incorrect token address for time locked amount");
        }
    }
}
