// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
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
import { RateProviderMock } from "@balancer-labs/v3-vault/contracts/test/RateProviderMock.sol";
import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { ECLPSurgeHookMock } from "../../contracts/test/ECLPSurgeHookMock.sol";
import { ECLPSurgeHookDeployer } from "./utils/ECLPSurgeHookDeployer.sol";
import { ECLPSurgeHook } from "../../contracts/ECLPSurgeHook.sol";

abstract contract ECLPSurgeHookBaseTest is BaseVaultTest, ECLPSurgeHookDeployer {
    using ArrayHelpers for *;
    using CastingHelpers for *;
    using FixedPoint for uint256;

    uint256 internal constant DEFAULT_AMP_FACTOR = 200;
    uint256 constant DEFAULT_POOL_TOKEN_COUNT = 2;

    uint256 internal wethIdx;
    uint256 internal usdcIdx;
    uint256 internal wethRate;

    ECLPSurgeHookMock internal eclpSurgeHookMock;
    IGyroECLPPool.DerivedEclpParams private derivedECLPParams;
    IGyroECLPPool.EclpParams private eclpParams;
    IRateProvider[] private rateProviders;

    function setUp() public override {
        (eclpParams, derivedECLPParams) = _setupEclpParams();

        super.setUp();

        // Allow router to burn BPT tokens.
        vm.prank(lp);
        IERC20(pool).approve(address(router), MAX_UINT256);
    }

    function _setupEclpParams()
        internal
        pure
        virtual
        returns (IGyroECLPPool.EclpParams memory eclpParams, IGyroECLPPool.DerivedEclpParams memory derivedECLPParams);
    function _getWethRate() internal pure virtual returns (uint256 wethRate);
    function _balancePool()
        internal
        virtual
        returns (uint256[] memory initialBalancesRaw, uint256[] memory initialBalancesScaled18);

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

        (wethIdx, usdcIdx) = getSortedIndexes(address(weth), address(usdc));
        wethRate = _getWethRate();

        RateProviderMock wethRateProvider = new RateProviderMock();
        wethRateProvider.mockRate(wethRate);
        rateProviders = new IRateProvider[](2);
        rateProviders[wethIdx] = IRateProvider(address(wethRateProvider));

        newPool = GyroECLPPoolFactory(poolFactory).create(
            "Gyro E-CLP Pool",
            "ECLP-POOL",
            vault.buildTokenConfig(tokens.asIERC20(), rateProviders),
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
        (uint256[] memory initialBalancesRaw, uint256[] memory initialBalancesScaled18) = _balancePool();

        // Add a large amount, so it surges.
        uint256[] memory amountsInRaw = new uint256[](2);
        amountsInRaw[usdcIdx] = 200e18;

        uint256[] memory expectedBalancesAfterAddScaled18 = new uint256[](2);
        expectedBalancesAfterAddScaled18[wethIdx] = initialBalancesScaled18[wethIdx];
        // Raw and Scaled18 USDC amounts are the same.
        expectedBalancesAfterAddScaled18[usdcIdx] = initialBalancesScaled18[usdcIdx] + amountsInRaw[usdcIdx];

        ECLPSurgeHook.SurgeFeeData memory surgeFeeData = eclpSurgeHookMock.getSurgeFeeData(pool);

        // Add USDC --> more unbalanced.
        uint256 oldTotalImbalance;
        uint256 newTotalImbalance;

        {
            (int256 a, int256 b) = eclpSurgeHookMock.computeOffsetFromBalances(
                initialBalancesScaled18,
                eclpParams,
                derivedECLPParams
            );
            oldTotalImbalance = eclpSurgeHookMock.computeImbalance(initialBalancesScaled18, eclpParams, a, b);
        }

        {
            (int256 a, int256 b) = eclpSurgeHookMock.computeOffsetFromBalances(
                expectedBalancesAfterAddScaled18,
                eclpParams,
                derivedECLPParams
            );
            newTotalImbalance = eclpSurgeHookMock.computeImbalance(expectedBalancesAfterAddScaled18, eclpParams, a, b);
        }

        assertTrue(
            eclpSurgeHookMock.isSurging(surgeFeeData.thresholdPercentage, oldTotalImbalance, newTotalImbalance),
            "Not surging after add"
        );

        vm.expectRevert(IVaultErrors.AfterAddLiquidityHookFailed.selector);
        vm.prank(alice);
        router.addLiquidityUnbalanced(pool, amountsInRaw, 0, false, "");

        // Proportional is always fine
        vm.prank(alice);
        router.addLiquidityProportional(pool, initialBalancesRaw, 1e18, false, bytes(""));
    }

    function testUnbalancedAddLiquidityWhenNotSurging() public {
        // Start with a balanced pool.
        (, uint256[] memory initialBalancesScaled18) = _balancePool();

        // Add a small amount, so it does not surge.
        uint256[] memory amountsInRaw = new uint256[](2);
        amountsInRaw[usdcIdx] = 1e18;

        uint256[] memory expectedBalancesAfterAddScaled18 = new uint256[](2);
        expectedBalancesAfterAddScaled18[wethIdx] = initialBalancesScaled18[wethIdx];
        // Raw and Scaled18 USDC amounts are the same.
        expectedBalancesAfterAddScaled18[usdcIdx] = initialBalancesScaled18[usdcIdx] + amountsInRaw[usdcIdx];

        ECLPSurgeHook.SurgeFeeData memory surgeFeeData = eclpSurgeHookMock.getSurgeFeeData(pool);

        uint256 oldTotalImbalance;
        uint256 newTotalImbalance;

        {
            (int256 a, int256 b) = eclpSurgeHookMock.computeOffsetFromBalances(
                initialBalancesScaled18,
                eclpParams,
                derivedECLPParams
            );
            oldTotalImbalance = eclpSurgeHookMock.computeImbalance(initialBalancesScaled18, eclpParams, a, b);
        }

        {
            (int256 a, int256 b) = eclpSurgeHookMock.computeOffsetFromBalances(
                expectedBalancesAfterAddScaled18,
                eclpParams,
                derivedECLPParams
            );
            newTotalImbalance = eclpSurgeHookMock.computeImbalance(expectedBalancesAfterAddScaled18, eclpParams, a, b);
        }

        assertFalse(
            eclpSurgeHookMock.isSurging(surgeFeeData.thresholdPercentage, oldTotalImbalance, newTotalImbalance),
            "Surging after add"
        );

        // Does not revert.
        vm.prank(alice);
        router.addLiquidityUnbalanced(pool, amountsInRaw, 0, false, "");
    }

    function testRemoveLiquidityWhenSurging() public {
        // Start with a balanced pool.
        (, uint256[] memory initialBalancesScaled18) = _balancePool();

        // Remove a large amount, so it surges.
        uint256[] memory amountsOutRaw = new uint256[](2);
        amountsOutRaw[usdcIdx] = 200e18;

        uint256[] memory expectedBalancesAfterRemoveScaled18 = new uint256[](2);
        expectedBalancesAfterRemoveScaled18[wethIdx] = initialBalancesScaled18[wethIdx];
        // Raw and Scaled18 USDC amounts are the same.
        expectedBalancesAfterRemoveScaled18[usdcIdx] = initialBalancesScaled18[usdcIdx] - amountsOutRaw[usdcIdx];

        ECLPSurgeHook.SurgeFeeData memory surgeFeeData = eclpSurgeHookMock.getSurgeFeeData(pool);

        // Remove USDC --> more unbalanced.
        uint256 oldTotalImbalance;
        uint256 newTotalImbalance;

        {
            (int256 a, int256 b) = eclpSurgeHookMock.computeOffsetFromBalances(
                initialBalancesScaled18,
                eclpParams,
                derivedECLPParams
            );
            oldTotalImbalance = eclpSurgeHookMock.computeImbalance(initialBalancesScaled18, eclpParams, a, b);
        }

        {
            (int256 a, int256 b) = eclpSurgeHookMock.computeOffsetFromBalances(
                expectedBalancesAfterRemoveScaled18,
                eclpParams,
                derivedECLPParams
            );
            newTotalImbalance = eclpSurgeHookMock.computeImbalance(
                expectedBalancesAfterRemoveScaled18,
                eclpParams,
                a,
                b
            );
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
            amountsOutRaw[usdcIdx],
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
        (, uint256[] memory initialBalancesScaled18) = _balancePool();

        // Remove a small amount, so it does not surge.
        uint256[] memory amountsOutRaw = new uint256[](2);
        amountsOutRaw[usdcIdx] = 1e18;

        uint256[] memory expectedBalancesAfterRemoveScaled18 = new uint256[](2);
        expectedBalancesAfterRemoveScaled18[wethIdx] = initialBalancesScaled18[wethIdx];
        // Raw and Scaled18 USDC amounts are the same.
        expectedBalancesAfterRemoveScaled18[usdcIdx] = initialBalancesScaled18[usdcIdx] - amountsOutRaw[usdcIdx];

        ECLPSurgeHook.SurgeFeeData memory surgeFeeData = eclpSurgeHookMock.getSurgeFeeData(pool);

        // Should not surge, close to balance.
        uint256 oldTotalImbalance;
        uint256 newTotalImbalance;

        {
            (int256 a, int256 b) = eclpSurgeHookMock.computeOffsetFromBalances(
                initialBalancesScaled18,
                eclpParams,
                derivedECLPParams
            );
            oldTotalImbalance = eclpSurgeHookMock.computeImbalance(initialBalancesScaled18, eclpParams, a, b);
        }

        {
            (int256 a, int256 b) = eclpSurgeHookMock.computeOffsetFromBalances(
                expectedBalancesAfterRemoveScaled18,
                eclpParams,
                derivedECLPParams
            );
            newTotalImbalance = eclpSurgeHookMock.computeImbalance(
                expectedBalancesAfterRemoveScaled18,
                eclpParams,
                a,
                b
            );
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
            amountsOutRaw[usdcIdx],
            false,
            bytes("")
        );
    }

    struct SwapTestLocals {
        uint256[] initialBalancesRaw;
        uint256[] initialBalancesScaled18;
        SwapKind kind;
        uint256 wethRate;
        uint256 amountGivenScaled18;
        uint256 swapFeePercentage;
        uint256 actualSwapFeePercentage;
        uint256 actualAmountInRaw;
        uint256 actualAmountOutRaw;
        uint256 expectedAmountInScaled18;
        uint256 expectedAmountOutScaled18;
    }

    function testSwap__Fuzz(uint256 amountGivenScaled18, uint256 swapFeePercentageRaw, uint256 kindRaw) public {
        (, uint256[] memory initialBalancesScaled18) = _balancePool();

        SwapKind kind = SwapKind(bound(kindRaw, 0, 1));
        {
            uint256 amountGivenUpperLimit = kind == SwapKind.EXACT_IN
                ? initialBalancesScaled18[usdcIdx] / 5
                : initialBalancesScaled18[wethIdx] / 10;
            amountGivenScaled18 = bound(amountGivenScaled18, amountGivenUpperLimit / 100, amountGivenUpperLimit);
        }

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
                amountGivenScaled18.divDown(wethRate),
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
            initialBalancesScaled18
        );

        BaseVaultTest.Balances memory balancesAfter = getBalances(alice);

        uint256 actualAmountOutRaw = balancesAfter.aliceTokens[wethIdx] - balancesBefore.aliceTokens[wethIdx];
        uint256 actualAmountInRaw = balancesBefore.aliceTokens[usdcIdx] - balancesAfter.aliceTokens[usdcIdx];

        uint256 expectedAmountOutScaled18;
        uint256 expectedAmountInScaled18;
        if (kind == SwapKind.EXACT_IN) {
            expectedAmountInScaled18 = amountGivenScaled18;
            uint256 swapAmount = amountGivenScaled18.mulUp(actualSwapFeePercentage);

            (uint256 amountCalculatedScaled18, , ) = eclpSurgeHookMock.computeSwap(
                PoolSwapParams({
                    kind: kind,
                    indexIn: usdcIdx,
                    indexOut: wethIdx,
                    amountGivenScaled18: expectedAmountInScaled18 - swapAmount,
                    balancesScaled18: initialBalancesScaled18,
                    router: address(0),
                    userData: bytes("")
                }),
                eclpParams,
                derivedECLPParams
            );

            expectedAmountOutScaled18 = amountCalculatedScaled18;
        } else {
            expectedAmountOutScaled18 = amountGivenScaled18;
            (uint256 amountCalculatedScaled18, , ) = eclpSurgeHookMock.computeSwap(
                PoolSwapParams({
                    kind: kind,
                    indexIn: usdcIdx,
                    indexOut: wethIdx,
                    amountGivenScaled18: expectedAmountOutScaled18,
                    balancesScaled18: initialBalancesScaled18,
                    router: address(0),
                    userData: bytes("")
                }),
                eclpParams,
                derivedECLPParams
            );
            expectedAmountInScaled18 =
                amountCalculatedScaled18 +
                amountCalculatedScaled18.mulDivUp(actualSwapFeePercentage, actualSwapFeePercentage.complement());
        }

        // The vault converts the pool balances from raw to scaled18, and the balance of WETH loses a bit of precision.
        // Amount In is in USDC, so scaled18 and raw are the same.
        assertApproxEqAbs(expectedAmountInScaled18, actualAmountInRaw, 1e6, "Amount in should be expectedAmountIn");
        // Amount Out is in WETH, so we need to convert scaled18 to raw to compare with the actual swap.
        assertApproxEqAbs(
            expectedAmountOutScaled18.divDown(wethRate),
            actualAmountOutRaw,
            1e6,
            "Amount out should be expectedAmountOut"
        );
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
}
