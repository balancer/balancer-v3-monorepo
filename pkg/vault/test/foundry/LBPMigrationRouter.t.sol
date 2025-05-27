// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { ILBPool } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPool.sol";
import { IWeightedPool } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/IWeightedPool.sol";
import { ILBPMigrationRouter } from "@balancer-labs/v3-interfaces/contracts/vault/ILBPMigrationRouter.sol";
import {
    PoolConfig,
    TokenConfig,
    TokenInfo,
    TokenType,
    PoolRoleAccounts
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { LBPMigrationRouter } from "@balancer-labs/v3-vault/contracts/LBPMigrationRouter.sol";
import { WeightedPoolFactory } from "@balancer-labs/v3-pool-weighted/contracts/WeightedPoolFactory.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";

import { BaseLBPTest } from "@balancer-labs/v3-pool-weighted/test/foundry/utils/BaseLBPTest.sol";
import {
    WeightedPoolContractsDeployer
} from "@balancer-labs/v3-pool-weighted/test/foundry/utils/WeightedPoolContractsDeployer.sol";

contract LBPMigrationRouterTest is BaseLBPTest, WeightedPoolContractsDeployer {
    using ArrayHelpers for *;

    string internal constant POOL_NAME = "Weighted Pool";
    string internal constant POOL_SYMBOL = "WP";

    LBPMigrationRouter lbpMigrationRouter;
    address treasury = makeAddr("treasury");

    function setUp() public override {
        super.setUp();

        WeightedPoolFactory weightedPoolFactory = deployWeightedPoolFactory(
            IVault(address(vault)),
            365 days,
            "Weighted Factory v1",
            "Weighted Pool v1"
        );

        lbpMigrationRouter = new LBPMigrationRouter(IVault(address(vault)), weightedPoolFactory, treasury);
    }

    function testMigrateLiquidity() external {
        vm.warp(ILBPool(pool).getLBPoolImmutableData().endTime + 1);

        address poolHooksContract = address(0);
        uint256[] memory weights = [50e16, uint256(50e16)].toMemoryArray();
        PoolRoleAccounts memory poolRoleAccounts = PoolRoleAccounts({
            pauseManager: makeAddr("pauseManager"),
            swapFeeManager: makeAddr("swapFeeManager"),
            poolCreator: address(0)
        });

        vm.startPrank(bob);

        uint256 lbpBPTBalanceBefore = IERC20(pool).balanceOf(bob);
        IERC20(pool).approve(address(lbpMigrationRouter), lbpBPTBalanceBefore);

        uint256[] memory initBalances = [poolInitAmount / 2, poolInitAmount / 3].toMemoryArray();
        (IWeightedPool weightedPool, ) = lbpMigrationRouter.migrateLiquidity(
            ILBPool(pool),
            initBalances,
            0, // minAddBptAmountOut
            new uint256[](2), // minRemoveAmountsOut
            ILBPMigrationRouter.WeightedPoolParams({
                name: POOL_NAME,
                symbol: POOL_SYMBOL,
                normalizedWeights: weights,
                roleAccounts: poolRoleAccounts,
                swapFeePercentage: DEFAULT_SWAP_FEE_PERCENTAGE,
                poolHooksContract: poolHooksContract,
                enableDonation: true,
                disableUnbalancedLiquidity: true,
                salt: bytes32(0)
            })
        );

        vm.stopPrank();

        (IERC20[] memory tokens, TokenInfo[] memory tokenInfo, , ) = vault.getPoolTokenInfo(address(weightedPool));
        (IERC20[] memory lbpTokens, TokenInfo[] memory lbpTokenInfo, , uint256[] memory lbpBalancesBefore) = vault
            .getPoolTokenInfo(address(weightedPool));

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
                true,
                "Disable unbalanced liquidity should be true"
            );
            assertEq(poolConfig.liquidityManagement.enableDonation, true, "Enable donation should be true");

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
            // Check that the weighted pool balance is correct
            uint256[] memory balancesLiveScaled18 = vault.getCurrentLiveBalances(address(weightedPool));
            assertEq(
                balancesLiveScaled18[projectIdx],
                initBalances[projectIdx],
                "Live balance mismatch for project token"
            );
            assertEq(
                balancesLiveScaled18[reserveIdx],
                initBalances[reserveIdx],
                "Live balance mismatch for reserve token"
            );

            // Check bob's balances
            assertEq(IERC20(pool).balanceOf(bob), 0, "Bob should not hold any LBP BPT after migration");
            assertGt(tokens[projectIdx].balanceOf(bob), 0, "Bob should have received project tokens after migration");
            assertGt(tokens[reserveIdx].balanceOf(bob), 0, "Bob should have received reserve tokens after migration");

            // Check lbpMigrationRouter balances
            assertEq(
                IERC20(address(weightedPool)).balanceOf(address(lbpMigrationRouter)),
                0,
                "Router should not hold any Weighted Pool BPT after migration"
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

            // Check treasury balances
            assertEq(
                tokens[projectIdx].balanceOf(address(treasury)),
                lbpBalancesBefore[projectIdx] - initBalances[projectIdx],
                "Treasury should hold the correct amount of project tokens after migration"
            );
            assertEq(
                tokens[reserveIdx].balanceOf(address(treasury)),
                lbpBalancesBefore[reserveIdx] - initBalances[reserveIdx],
                "Treasury should hold the correct amount of reserve tokens after migration"
            );
        }
    }

    function testMigrateLiquidityRevertsIfLBPWeightsNotFinalized() external {
        PoolRoleAccounts memory poolRoleAccounts;

        vm.expectRevert(abi.encodeWithSelector(ILBPMigrationRouter.LBPWeightsNotFinalized.selector, pool));
        vm.prank(bob);
        lbpMigrationRouter.migrateLiquidity(
            ILBPool(pool),
            [poolInitAmount, poolInitAmount].toMemoryArray(),
            0, // minAddBptAmountOut
            new uint256[](2), // minRemoveAmountsOut
            ILBPMigrationRouter.WeightedPoolParams({
                name: POOL_NAME,
                symbol: POOL_SYMBOL,
                normalizedWeights: [50e16, uint256(50e16)].toMemoryArray(),
                roleAccounts: poolRoleAccounts,
                swapFeePercentage: DEFAULT_SWAP_FEE_PERCENTAGE,
                poolHooksContract: address(0),
                enableDonation: true,
                disableUnbalancedLiquidity: true,
                salt: bytes32(0)
            })
        );
    }

    function testMigrateLiquidityRevertsIfInsufficientInputAmount() external {
        vm.warp(ILBPool(pool).getLBPoolImmutableData().endTime + 1);

        PoolRoleAccounts memory poolRoleAccounts;

        uint256 snapshotId = vm.snapshot();
        uint256 bptAmount = IERC20(pool).balanceOf(bob);
        _prankStaticCall();
        uint256[] memory amountsOut = router.queryRemoveLiquidityProportional(pool, bptAmount, bob, new bytes(0));
        vm.revertTo(snapshotId);

        vm.startPrank(bob);
        uint256 lbpBPTBalanceBefore = IERC20(pool).balanceOf(bob);
        IERC20(pool).approve(address(lbpMigrationRouter), lbpBPTBalanceBefore);

        vm.expectRevert(
            abi.encodeWithSelector(
                ILBPMigrationRouter.InsufficientInputAmount.selector,
                vault.getPoolTokens(pool)[0],
                amountsOut[0]
            )
        );
        lbpMigrationRouter.migrateLiquidity(
            ILBPool(pool),
            [poolInitAmount * 2, poolInitAmount * 2].toMemoryArray(),
            0, // minAddBptAmountOut
            new uint256[](2), // minRemoveAmountsOut
            ILBPMigrationRouter.WeightedPoolParams({
                name: POOL_NAME,
                symbol: POOL_SYMBOL,
                normalizedWeights: [50e16, uint256(50e16)].toMemoryArray(),
                roleAccounts: poolRoleAccounts,
                swapFeePercentage: DEFAULT_SWAP_FEE_PERCENTAGE,
                poolHooksContract: address(0),
                enableDonation: true,
                disableUnbalancedLiquidity: true,
                salt: bytes32(0)
            })
        );
        vm.stopPrank();
    }

    function testMigrateLiquidityRevertsIfSenderIsNotPoolOwner() external {
        vm.warp(ILBPool(pool).getLBPoolImmutableData().endTime + 1);

        PoolRoleAccounts memory poolRoleAccounts;

        vm.expectRevert(abi.encodeWithSelector(ILBPMigrationRouter.SenderIsNotLBPOwner.selector, bob));
        vm.prank(alice);
        lbpMigrationRouter.migrateLiquidity(
            ILBPool(pool),
            [poolInitAmount * 2, poolInitAmount * 2].toMemoryArray(),
            0, // minAddBptAmountOut
            new uint256[](2), // minRemoveAmountsOut
            ILBPMigrationRouter.WeightedPoolParams({
                name: POOL_NAME,
                symbol: POOL_SYMBOL,
                normalizedWeights: [50e16, uint256(50e16)].toMemoryArray(),
                roleAccounts: poolRoleAccounts,
                swapFeePercentage: DEFAULT_SWAP_FEE_PERCENTAGE,
                poolHooksContract: address(0),
                enableDonation: true,
                disableUnbalancedLiquidity: true,
                salt: bytes32(0)
            })
        );
    }

    function testMigrateLiquidityRevertsIfRemoveAmountsLessThenMin() external {
        vm.warp(ILBPool(pool).getLBPoolImmutableData().endTime + 1);

        uint256 snapshotId = vm.snapshot();
        uint256 bptAmount = IERC20(pool).balanceOf(bob);
        _prankStaticCall();
        uint256[] memory amountsOut = router.queryRemoveLiquidityProportional(pool, bptAmount, bob, new bytes(0));
        vm.revertTo(snapshotId);

        PoolRoleAccounts memory poolRoleAccounts;

        vm.startPrank(bob);
        uint256 lbpBPTBalanceBefore = IERC20(pool).balanceOf(bob);
        IERC20(pool).approve(address(lbpMigrationRouter), lbpBPTBalanceBefore);

        vm.expectRevert(
            abi.encodeWithSelector(
                IVaultErrors.AmountOutBelowMin.selector,
                vault.getPoolTokens(pool)[0],
                amountsOut[0],
                MAX_UINT128
            )
        );
        lbpMigrationRouter.migrateLiquidity(
            ILBPool(pool),
            [poolInitAmount, poolInitAmount].toMemoryArray(),
            0, // minAddBptAmountOut
            [MAX_UINT128, MAX_UINT128].toMemoryArray(), // minRemoveAmountsOut
            ILBPMigrationRouter.WeightedPoolParams({
                name: POOL_NAME,
                symbol: POOL_SYMBOL,
                normalizedWeights: [50e16, uint256(50e16)].toMemoryArray(),
                roleAccounts: poolRoleAccounts,
                swapFeePercentage: DEFAULT_SWAP_FEE_PERCENTAGE,
                poolHooksContract: address(0),
                enableDonation: true,
                disableUnbalancedLiquidity: true,
                salt: bytes32(0)
            })
        );
        vm.stopPrank();
    }

    function testMigrateLiquidityRevertsIfAddBptAmountOutBelowMin() external {
        vm.warp(ILBPool(pool).getLBPoolImmutableData().endTime + 1);

        PoolRoleAccounts memory poolRoleAccounts;
        ILBPMigrationRouter.WeightedPoolParams memory weightedPoolParams = ILBPMigrationRouter.WeightedPoolParams({
            name: POOL_NAME,
            symbol: POOL_SYMBOL,
            normalizedWeights: [50e16, uint256(50e16)].toMemoryArray(),
            roleAccounts: poolRoleAccounts,
            swapFeePercentage: DEFAULT_SWAP_FEE_PERCENTAGE,
            poolHooksContract: address(0),
            enableDonation: true,
            disableUnbalancedLiquidity: true,
            salt: bytes32(0)
        });

        vm.startPrank(bob);
        uint256 lbpBPTBalanceBefore = IERC20(pool).balanceOf(bob);
        IERC20(pool).approve(address(lbpMigrationRouter), lbpBPTBalanceBefore);
        vm.stopPrank();

        uint256[] memory exactAmountsIn = [poolInitAmount / 2, poolInitAmount / 2].toMemoryArray();
        uint256 snapshotId = vm.snapshot();
        _prankStaticCall();
        (, uint256 bptAmountOut) = lbpMigrationRouter.queryMigrateLiquidity(
            ILBPool(pool),
            exactAmountsIn,
            bob,
            weightedPoolParams
        );
        vm.revertTo(snapshotId);

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.BptAmountOutBelowMin.selector, bptAmountOut, MAX_UINT128));
        vm.prank(bob);
        lbpMigrationRouter.migrateLiquidity(
            ILBPool(pool),
            exactAmountsIn,
            MAX_UINT128, // minAddBptAmountOut
            new uint256[](2), // minRemoveAmountsOut
            weightedPoolParams
        );
    }
}
