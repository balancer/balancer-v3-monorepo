// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IGyroECLPPool } from "@balancer-labs/v3-interfaces/contracts/pool-gyro/IGyroECLPPool.sol";
import { PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { ScalingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ScalingHelpers.sol";
import { PoolSwapParams, SwapKind } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { GyroECLPPoolFactory } from "@balancer-labs/v3-pool-gyro/contracts/GyroECLPPoolFactory.sol";
import { CommonAuthentication } from "@balancer-labs/v3-vault/contracts/CommonAuthentication.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { ECLPSurgeHookMock } from "../../contracts/test/ECLPSurgeHookMock.sol";
import { ECLPSurgeHookDeployer } from "./utils/ECLPSurgeHookDeployer.sol";
import { ECLPSurgeHook } from "../../contracts/ECLPSurgeHook.sol";

contract ECLPSurgeHookTest is BaseVaultTest, ECLPSurgeHookDeployer {
    using ArrayHelpers for *;
    using CastingHelpers for *;
    using FixedPoint for uint256;

    uint256 internal constant DEFAULT_AMP_FACTOR = 200;
    uint256 constant DEFAULT_POOL_TOKEN_COUNT = 2;

    uint256 internal wethIdx;
    uint256 internal usdcIdx;

    ECLPSurgeHookMock internal eclpSurgeHookMock;
    IGyroECLPPool.EclpParams private eclpParams;
    IGyroECLPPool.DerivedEclpParams private derivedECLPParams;

    function setUp() public override {
        eclpParams = IGyroECLPPool.EclpParams({
            alpha: 3100000000000000000000,
            beta: 4400000000000000000000,
            c: 266047486094289,
            s: 999999964609366945,
            lambda: 20000000000000000000000
        });
        derivedECLPParams = IGyroECLPPool.DerivedEclpParams({
            tauAlpha: IGyroECLPPool.Vector2({
                x: -74906290317688162800819482607385924041,
                y: 66249888081733516165500078448108672943
            }),
            tauBeta: IGyroECLPPool.Vector2({
                x: 61281617359500229793875202705993079582,
                y: 79022549780450643715972436171311055791
            }),
            u: 36232449191667733617897641246115478,
            v: 79022548876385493056482320848126240168,
            w: 3398134415414370285204934569561736,
            z: -74906280678135799137829029450497780483,
            dSq: 99999999999999999958780685745704854600
        });

        super.setUp();

        (wethIdx, usdcIdx) = getSortedIndexes(address(weth), address(usdc));
        // Allow router to burn BPT tokens.
        vm.prank(lp);
        IERC20(pool).approve(address(router), MAX_UINT256);
    }

    function createPoolFactory() internal override returns (address) {
        return address(new GyroECLPPoolFactory(IVault(address(vault)), 365 days, "Factory v1", "Pool v1"));
    }

    function createHook() internal override returns (address) {
        vm.prank(poolFactory);
        eclpSurgeHookMock = deployECLPSurgeHookMock(
            vault,
            DEFAULT_MAX_SURGE_FEE_PERCENTAGE,
            DEFAULT_SURGE_THRESHOLD_PERCENTAGE,
            "Test"
        );
        vm.label(address(eclpSurgeHookMock), "ECLPSurgeHook");
        return address(eclpSurgeHookMock);
    }

    function _createPool(
        address[] memory tokens,
        string memory label
    ) internal override returns (address newPool, bytes memory poolArgs) {
        tokens = [address(weth), address(usdc)].toMemoryArray();
        PoolRoleAccounts memory roleAccounts;

        newPool = GyroECLPPoolFactory(poolFactory).create(
            "Gyro E-CLP Pool",
            "ECLP-POOL",
            vault.buildTokenConfig(tokens.asIERC20()),
            eclpParams,
            derivedECLPParams,
            roleAccounts,
            DEFAULT_SWAP_FEE_PERCENTAGE,
            poolHooksContract,
            false,
            false,
            ZERO_BYTES32
        );
        vm.label(address(newPool), label);

        return (
            address(newPool),
            abi.encode(
                IGyroECLPPool.GyroECLPPoolParams({
                    name: "Gyro E-CLP Pool",
                    symbol: "ECLP-POOL",
                    eclpParams: eclpParams,
                    derivedEclpParams: derivedECLPParams,
                    version: "Pool v1"
                }),
                vault
            )
        );
    }

    function testValidVault() public {
        vm.expectRevert(CommonAuthentication.VaultNotSet.selector);
        deployECLPSurgeHook(
            IVault(address(0)),
            DEFAULT_MAX_SURGE_FEE_PERCENTAGE,
            DEFAULT_SURGE_THRESHOLD_PERCENTAGE,
            ""
        );
    }

    function testSuccessfulRegistry() public view {
        assertEq(
            eclpSurgeHookMock.getSurgeThresholdPercentage(pool),
            DEFAULT_SURGE_THRESHOLD_PERCENTAGE,
            "Surge threshold is wrong"
        );
    }

    function testUnbalancedAddLiquidityWhenSurging() public {
        // Start with a balanced pool.
        uint256[] memory initialBalances = _balancePool();

        // Add a large amount, so it surges.
        uint256[] memory amountsIn = new uint256[](2);
        amountsIn[usdcIdx] = 200e18;

        uint256[] memory expectedBalancesAfterAdd = new uint256[](2);
        expectedBalancesAfterAdd[wethIdx] = initialBalances[wethIdx] + amountsIn[wethIdx];
        expectedBalancesAfterAdd[usdcIdx] = initialBalances[usdcIdx] + amountsIn[usdcIdx];

        ECLPSurgeHook.SurgeFeeData memory surgeFeeData = eclpSurgeHookMock.getSurgeFeeData(pool);

        // Add USDC --> more unbalanced.
        uint256 oldTotalImbalance;
        uint256 newTotalImbalance;

        {
            (int256 a, int256 b) = eclpSurgeHookMock.computeOffsetFromBalances(
                initialBalances,
                eclpParams,
                derivedECLPParams
            );
            oldTotalImbalance = eclpSurgeHookMock.computeImbalance(initialBalances, eclpParams, a, b);
        }

        {
            (int256 a, int256 b) = eclpSurgeHookMock.computeOffsetFromBalances(
                expectedBalancesAfterAdd,
                eclpParams,
                derivedECLPParams
            );
            newTotalImbalance = eclpSurgeHookMock.computeImbalance(expectedBalancesAfterAdd, eclpParams, a, b);
        }

        assertTrue(
            eclpSurgeHookMock.isSurging(surgeFeeData.thresholdPercentage, oldTotalImbalance, newTotalImbalance),
            "Not surging after add"
        );

        vm.expectRevert(IVaultErrors.AfterAddLiquidityHookFailed.selector);
        vm.prank(alice);
        router.addLiquidityUnbalanced(pool, amountsIn, 0, false, "");

        // Proportional is always fine
        vm.prank(alice);
        router.addLiquidityProportional(pool, initialBalances, 1e18, false, bytes(""));
    }

    function testUnbalancedAddLiquidityWhenNotSurging() public {
        // Start with a balanced pool.
        uint256[] memory initialBalances = _balancePool();

        // Add a small amount, so it does not surge.
        uint256[] memory amountsIn = new uint256[](2);
        amountsIn[usdcIdx] = 1e18;

        uint256[] memory expectedBalancesAfterAdd = new uint256[](2);
        expectedBalancesAfterAdd[wethIdx] = initialBalances[wethIdx] + amountsIn[wethIdx];
        expectedBalancesAfterAdd[usdcIdx] = initialBalances[usdcIdx] + amountsIn[usdcIdx];

        ECLPSurgeHook.SurgeFeeData memory surgeFeeData = eclpSurgeHookMock.getSurgeFeeData(pool);

        uint256 oldTotalImbalance;
        uint256 newTotalImbalance;

        {
            (int256 a, int256 b) = eclpSurgeHookMock.computeOffsetFromBalances(
                initialBalances,
                eclpParams,
                derivedECLPParams
            );
            oldTotalImbalance = eclpSurgeHookMock.computeImbalance(initialBalances, eclpParams, a, b);
        }

        {
            (int256 a, int256 b) = eclpSurgeHookMock.computeOffsetFromBalances(
                expectedBalancesAfterAdd,
                eclpParams,
                derivedECLPParams
            );
            newTotalImbalance = eclpSurgeHookMock.computeImbalance(expectedBalancesAfterAdd, eclpParams, a, b);
        }

        assertFalse(
            eclpSurgeHookMock.isSurging(surgeFeeData.thresholdPercentage, oldTotalImbalance, newTotalImbalance),
            "Surging after add"
        );

        // Does not revert.
        vm.prank(alice);
        router.addLiquidityUnbalanced(pool, amountsIn, 0, false, "");
    }

    function testRemoveLiquidityWhenSurging() public {
        // Start with a balanced pool.
        uint256[] memory initialBalances = _balancePool();

        // Remove a large amount, so it surges.
        uint256[] memory amountsOut = new uint256[](2);
        amountsOut[usdcIdx] = 200e18;

        uint256[] memory expectedBalancesAfterRemove = new uint256[](2);
        expectedBalancesAfterRemove[wethIdx] = initialBalances[wethIdx] - amountsOut[wethIdx];
        expectedBalancesAfterRemove[usdcIdx] = initialBalances[usdcIdx] - amountsOut[usdcIdx];

        ECLPSurgeHook.SurgeFeeData memory surgeFeeData = eclpSurgeHookMock.getSurgeFeeData(pool);

        // Remove USDC --> more unbalanced.
        uint256 oldTotalImbalance;
        uint256 newTotalImbalance;

        {
            (int256 a, int256 b) = eclpSurgeHookMock.computeOffsetFromBalances(
                initialBalances,
                eclpParams,
                derivedECLPParams
            );
            oldTotalImbalance = eclpSurgeHookMock.computeImbalance(initialBalances, eclpParams, a, b);
        }

        {
            (int256 a, int256 b) = eclpSurgeHookMock.computeOffsetFromBalances(
                expectedBalancesAfterRemove,
                eclpParams,
                derivedECLPParams
            );
            newTotalImbalance = eclpSurgeHookMock.computeImbalance(expectedBalancesAfterRemove, eclpParams, a, b);
        }

        // Pool needs to be surging after remove, so the unbalanced liquidity operation reverts.
        assertTrue(
            eclpSurgeHookMock.isSurging(surgeFeeData.thresholdPercentage, oldTotalImbalance, newTotalImbalance),
            "Not surging after remove"
        );

        uint256 bptBalance = IERC20(pool).balanceOf(lp);

        vm.expectRevert(IVaultErrors.AfterRemoveLiquidityHookFailed.selector);
        vm.prank(lp);
        router.removeLiquiditySingleTokenExactOut(
            address(pool),
            bptBalance,
            usdc,
            amountsOut[usdcIdx],
            false,
            bytes("")
        );

        uint256[] memory minAmountsOut = new uint256[](2);
        // Proportional is always fine
        vm.prank(lp);
        router.removeLiquidityProportional(pool, bptBalance / 2, minAmountsOut, false, bytes(""));
    }

    function testUnbalancedRemoveLiquidityWhenNotSurging() public {
        // Start with a balanced pool.
        uint256[] memory initialBalances = _balancePool();

        // Remove a small amount, so it does not surge.
        uint256[] memory amountsOut = new uint256[](2);
        amountsOut[usdcIdx] = 1e18;

        uint256[] memory expectedBalancesAfterRemove = new uint256[](2);
        expectedBalancesAfterRemove[wethIdx] = initialBalances[wethIdx] - amountsOut[wethIdx];
        expectedBalancesAfterRemove[usdcIdx] = initialBalances[usdcIdx] - amountsOut[usdcIdx];

        ECLPSurgeHook.SurgeFeeData memory surgeFeeData = eclpSurgeHookMock.getSurgeFeeData(pool);

        // Should not surge, close to balance.
        uint256 oldTotalImbalance;
        uint256 newTotalImbalance;

        {
            (int256 a, int256 b) = eclpSurgeHookMock.computeOffsetFromBalances(
                initialBalances,
                eclpParams,
                derivedECLPParams
            );
            oldTotalImbalance = eclpSurgeHookMock.computeImbalance(initialBalances, eclpParams, a, b);
        }

        {
            (int256 a, int256 b) = eclpSurgeHookMock.computeOffsetFromBalances(
                expectedBalancesAfterRemove,
                eclpParams,
                derivedECLPParams
            );
            newTotalImbalance = eclpSurgeHookMock.computeImbalance(expectedBalancesAfterRemove, eclpParams, a, b);
        }

        assertFalse(
            eclpSurgeHookMock.isSurging(surgeFeeData.thresholdPercentage, oldTotalImbalance, newTotalImbalance),
            "Surging after remove"
        );

        uint256 bptBalance = IERC20(pool).balanceOf(lp);
        // Does not revert.
        vm.prank(lp);
        router.removeLiquiditySingleTokenExactOut(
            address(pool),
            bptBalance,
            usdc,
            amountsOut[usdcIdx],
            false,
            bytes("")
        );
    }

    function testSwap__Fuzz(uint256 amountGivenScaled18, uint256 swapFeePercentageRaw, uint256 kindRaw) public {
        amountGivenScaled18 = bound(amountGivenScaled18, 1e18, poolInitAmount / 2);
        SwapKind kind = SwapKind(bound(kindRaw, 0, 1));

        vault.manualUnsafeSetStaticSwapFeePercentage(pool, bound(swapFeePercentageRaw, 0, 1e16));
        uint256 swapFeePercentage = vault.getStaticSwapFeePercentage(pool);

        BaseVaultTest.Balances memory balancesBefore = getBalances(alice);

        if (kind == SwapKind.EXACT_IN) {
            vm.prank(alice);
            router.swapSingleTokenExactIn(pool, usdc, weth, amountGivenScaled18, 0, MAX_UINT256, false, bytes(""));
        } else {
            vm.prank(alice);
            router.swapSingleTokenExactOut(
                pool,
                usdc,
                weth,
                amountGivenScaled18,
                MAX_UINT256,
                MAX_UINT256,
                false,
                bytes("")
            );
        }

        uint256 actualSwapFeePercentage = _computeFee(
            amountGivenScaled18,
            kind,
            swapFeePercentage,
            [poolInitAmount, poolInitAmount].toMemoryArray()
        );

        BaseVaultTest.Balances memory balancesAfter = getBalances(alice);

        uint256 actualAmountOut = balancesAfter.aliceTokens[wethIdx] - balancesBefore.aliceTokens[wethIdx];
        uint256 actualAmountIn = balancesBefore.aliceTokens[usdcIdx] - balancesAfter.aliceTokens[usdcIdx];

        uint256 expectedAmountOut;
        uint256 expectedAmountIn;
        if (kind == SwapKind.EXACT_IN) {
            // extract swap fee
            expectedAmountIn = amountGivenScaled18;
            uint256 swapAmount = amountGivenScaled18.mulUp(actualSwapFeePercentage);

            (uint256 amountCalculatedScaled18, , ) = eclpSurgeHookMock.computeSwap(
                PoolSwapParams({
                    kind: kind,
                    indexIn: usdcIdx,
                    indexOut: wethIdx,
                    amountGivenScaled18: expectedAmountIn - swapAmount,
                    balancesScaled18: [poolInitAmount, poolInitAmount].toMemoryArray(),
                    router: address(0),
                    userData: bytes("")
                }),
                eclpParams,
                derivedECLPParams
            );

            expectedAmountOut = amountCalculatedScaled18;
        } else {
            expectedAmountOut = amountGivenScaled18;
            (uint256 amountCalculatedScaled18, , ) = eclpSurgeHookMock.computeSwap(
                PoolSwapParams({
                    kind: kind,
                    indexIn: usdcIdx,
                    indexOut: wethIdx,
                    amountGivenScaled18: expectedAmountOut,
                    balancesScaled18: [poolInitAmount, poolInitAmount].toMemoryArray(),
                    router: address(0),
                    userData: bytes("")
                }),
                eclpParams,
                derivedECLPParams
            );
            expectedAmountIn =
                amountCalculatedScaled18 +
                amountCalculatedScaled18.mulDivUp(actualSwapFeePercentage, actualSwapFeePercentage.complement());
        }

        assertEq(expectedAmountIn, actualAmountIn, "Amount in should be expectedAmountIn");
        assertEq(expectedAmountOut, actualAmountOut, "Amount out should be expectedAmountOut");
    }

    function _computeFee(
        uint256 amountGivenScaled18,
        SwapKind kind,
        uint256 swapFeePercentage,
        uint256[] memory balances
    ) private view returns (uint256) {
        (uint256 amountCalculatedScaled18, , ) = eclpSurgeHookMock.computeSwap(
            PoolSwapParams({
                kind: kind,
                indexIn: usdcIdx,
                indexOut: wethIdx,
                amountGivenScaled18: amountGivenScaled18,
                balancesScaled18: balances,
                router: address(0),
                userData: bytes("")
            }),
            eclpParams,
            derivedECLPParams
        );

        uint256[] memory newBalances = new uint256[](balances.length);
        ScalingHelpers.copyToArray(balances, newBalances);

        if (kind == SwapKind.EXACT_IN) {
            newBalances[usdcIdx] += amountGivenScaled18;
            newBalances[wethIdx] -= amountCalculatedScaled18;
        } else {
            newBalances[usdcIdx] += amountCalculatedScaled18;
            newBalances[wethIdx] -= amountGivenScaled18;
        }

        uint256 newTotalImbalance;
        uint256 oldTotalImbalance;

        {
            (int256 a, int256 b) = eclpSurgeHookMock.computeOffsetFromBalances(balances, eclpParams, derivedECLPParams);
            oldTotalImbalance = eclpSurgeHookMock.computeImbalance(balances, eclpParams, a, b);
        }

        {
            (int256 a, int256 b) = eclpSurgeHookMock.computeOffsetFromBalances(
                newBalances,
                eclpParams,
                derivedECLPParams
            );
            newTotalImbalance = eclpSurgeHookMock.computeImbalance(newBalances, eclpParams, a, b);
        }

        if (
            newTotalImbalance == 0 ||
            (newTotalImbalance <= oldTotalImbalance || newTotalImbalance <= DEFAULT_SURGE_THRESHOLD_PERCENTAGE)
        ) {
            return swapFeePercentage;
        }

        return
            swapFeePercentage +
            (eclpSurgeHookMock.getMaxSurgeFeePercentage(pool) - swapFeePercentage).mulDown(
                (newTotalImbalance - DEFAULT_SURGE_THRESHOLD_PERCENTAGE).divDown(
                    DEFAULT_SURGE_THRESHOLD_PERCENTAGE.complement()
                )
            );
    }

    function _balancePool() private returns (uint256[] memory initialBalances) {
        // Balances computed so that imbalance is close to 0 (0.64%).
        initialBalances = new uint256[](2);
        initialBalances[wethIdx] = 0.1e18;
        initialBalances[usdcIdx] = 500e18;
        vault.manualSetPoolBalances(pool, initialBalances, initialBalances);
    }
}
