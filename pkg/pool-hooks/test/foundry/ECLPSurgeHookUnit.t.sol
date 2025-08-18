// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { ISurgeHookCommon } from "@balancer-labs/v3-interfaces/contracts/pool-hooks/ISurgeHookCommon.sol";
import { ISurgeHookCommon } from "@balancer-labs/v3-interfaces/contracts/pool-hooks/ISurgeHookCommon.sol";
import { IGyroECLPPool } from "@balancer-labs/v3-interfaces/contracts/pool-gyro/IGyroECLPPool.sol";
import { IVaultExtension } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultExtension.sol";
import { PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { PoolSwapParams, SwapKind } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { GyroECLPPoolFactory } from "@balancer-labs/v3-pool-gyro/contracts/GyroECLPPoolFactory.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { ECLPSurgeHookMock } from "../../contracts/test/ECLPSurgeHookMock.sol";
import { ECLPSurgeHookDeployer } from "./utils/ECLPSurgeHookDeployer.sol";
import { ECLPSurgeHook } from "../../contracts/ECLPSurgeHook.sol";

contract ECLPSurgeHookUnitTest is BaseVaultTest, ECLPSurgeHookDeployer {
    using FixedPoint for uint256;
    using CastingHelpers for *;
    using ArrayHelpers for *;

    ECLPSurgeHookMock private hookMock;
    IGyroECLPPool.EclpParams private eclpParams;
    IGyroECLPPool.DerivedEclpParams private derivedECLPParams;
    uint256[] private balancesScaled18;
    uint256[] private peakBalancesScaled18;

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

        // Data from pool 0xf78556b9ccce5a6eb9476a4d086ea15f3790660a, Arbitrum.
        // Token A is WETH, and Token B is USDC.
        balancesScaled18 = [uint256(2948989424059932952), uint256(9513574260000000000000)].toMemoryArray();
        peakBalancesScaled18 = [uint256(2372852587012056561), uint256(11651374260000000000000)].toMemoryArray();
    }

    function createPoolFactory() internal override returns (address) {
        return address(new GyroECLPPoolFactory(IVault(address(vault)), 365 days, "Factory v1", "Pool v1"));
    }

    function createHook() internal override returns (address) {
        vm.prank(poolFactory);
        hookMock = deployECLPSurgeHookMock(
            vault,
            DEFAULT_MAX_SURGE_FEE_PERCENTAGE,
            DEFAULT_SURGE_THRESHOLD_PERCENTAGE,
            "Test"
        );
        vm.label(address(hookMock), "ECLPSurgeHook");
        return address(hookMock);
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

    function testPriceComputation() public view {
        // Price computed offchain.
        uint256 expectedPrice = 3663201029819534758509;

        uint256 actualPrice = hookMock.computePriceFromBalances(balancesScaled18, eclpParams, derivedECLPParams);
        assertEq(actualPrice, expectedPrice, "Prices do not match");
    }

    function testIsSurgingWithSwapTowardsLiquidityPeak() public view {
        // Current price is 3663 and peak price is sine/cosine = s/c = 3758. The following swap will increase the
        // price, bringing the pool closer to the peak of liquidity, so isSurging must be false.

        // 100 USDC in.
        uint256 amountGivenScaled18 = 100e18;

        PoolSwapParams memory request = PoolSwapParams({
            kind: SwapKind.EXACT_IN,
            amountGivenScaled18: amountGivenScaled18,
            balancesScaled18: balancesScaled18,
            indexIn: 1,
            indexOut: 0,
            router: address(router),
            userData: bytes("")
        });

        (uint256 amountCalculatedScaled18, , ) = hookMock.computeSwap(request, eclpParams, derivedECLPParams);

        uint256[] memory balancesUpdated = new uint256[](2);
        balancesUpdated[0] = balancesScaled18[0] - amountCalculatedScaled18;
        balancesUpdated[1] = balancesScaled18[1] + amountGivenScaled18;

        (int256 a, int256 b) = hookMock.computeOffsetFromBalances(balancesScaled18, eclpParams, derivedECLPParams);
        uint256 oldImbalance = hookMock.computeImbalance(balancesScaled18, eclpParams, a, b);
        // a and b are the same, since the swap without fees do not modify the invariant.
        uint256 newImbalance = hookMock.computeImbalance(balancesUpdated, eclpParams, a, b);

        assertLt(newImbalance, oldImbalance, "Old imbalance < New imbalance");
        // If newImbalance is smaller than threshold, isSurging function is not tested.
        assertGt(newImbalance, DEFAULT_SURGE_THRESHOLD_PERCENTAGE, "New imbalance < Surge Threshold");
        assertFalse(
            hookMock.isSurging(uint64(DEFAULT_SURGE_THRESHOLD_PERCENTAGE), oldImbalance, newImbalance),
            "Pool is surging"
        );
    }

    function testIsSurgingWithSwapTowardsEdge() public view {
        // Current price is 3663 and peak price is sine/cosine = s/c = 3758. The following swap will decrease the
        // price, bringing the pool farther from the peak of liquidity, so isSurging must be true.

        // 100 USDC out.
        uint256 amountGivenScaled18 = 100e18;

        PoolSwapParams memory request = PoolSwapParams({
            kind: SwapKind.EXACT_OUT,
            amountGivenScaled18: amountGivenScaled18,
            balancesScaled18: balancesScaled18,
            indexIn: 0,
            indexOut: 1,
            router: address(router),
            userData: bytes("")
        });

        (uint256 amountCalculatedScaled18, , ) = hookMock.computeSwap(request, eclpParams, derivedECLPParams);

        uint256[] memory balancesUpdated = new uint256[](2);
        balancesUpdated[0] = balancesScaled18[0] + amountCalculatedScaled18;
        balancesUpdated[1] = balancesScaled18[1] - amountGivenScaled18;

        (int256 a, int256 b) = hookMock.computeOffsetFromBalances(balancesScaled18, eclpParams, derivedECLPParams);
        uint256 oldImbalance = hookMock.computeImbalance(balancesScaled18, eclpParams, a, b);
        // a and b are the same, since the swap without fees do not modify the invariant.
        uint256 newImbalance = hookMock.computeImbalance(balancesUpdated, eclpParams, a, b);

        assertGt(newImbalance, oldImbalance, "Old imbalance > New imbalance");
        // If newImbalance is smaller than threshold, isSurging function is not tested.
        assertGt(newImbalance, DEFAULT_SURGE_THRESHOLD_PERCENTAGE, "New imbalance < Surge Threshold");
        assertTrue(
            hookMock.isSurging(uint64(DEFAULT_SURGE_THRESHOLD_PERCENTAGE), oldImbalance, newImbalance),
            "Pool is not surging"
        );
    }

    function testIsSurging__Fuzz(uint256 amountOutScaled18, uint256 tokenOutIndex) public view {
        tokenOutIndex = bound(tokenOutIndex, 0, 1);
        amountOutScaled18 = bound(amountOutScaled18, 1e6, peakBalancesScaled18[tokenOutIndex].mulDown(99e16));

        PoolSwapParams memory request = PoolSwapParams({
            kind: SwapKind.EXACT_OUT,
            amountGivenScaled18: amountOutScaled18,
            balancesScaled18: peakBalancesScaled18,
            indexIn: 1 - tokenOutIndex,
            indexOut: tokenOutIndex,
            router: address(router),
            userData: bytes("")
        });

        (uint256 amountInScaled18, , ) = hookMock.computeSwap(request, eclpParams, derivedECLPParams);

        uint256[] memory balancesUpdated = new uint256[](2);
        balancesUpdated[0] = peakBalancesScaled18[0] + amountInScaled18;
        balancesUpdated[1] = peakBalancesScaled18[1] - amountOutScaled18;

        (int256 a, int256 b) = hookMock.computeOffsetFromBalances(peakBalancesScaled18, eclpParams, derivedECLPParams);
        uint256 oldImbalance = hookMock.computeImbalance(peakBalancesScaled18, eclpParams, a, b);
        // a and b are the same, since the swap without fees do not modify the invariant.
        uint256 newImbalance = hookMock.computeImbalance(balancesUpdated, eclpParams, a, b);

        if (oldImbalance < newImbalance) {
            if (newImbalance > DEFAULT_SURGE_THRESHOLD_PERCENTAGE) {
                assertTrue(
                    hookMock.isSurging(uint64(DEFAULT_SURGE_THRESHOLD_PERCENTAGE), oldImbalance, newImbalance),
                    "Pool is not surging"
                );
            } else {
                assertFalse(
                    hookMock.isSurging(uint64(DEFAULT_SURGE_THRESHOLD_PERCENTAGE), oldImbalance, newImbalance),
                    "Pool is surging"
                );
            }
        } else {
            assertFalse(
                hookMock.isSurging(uint64(DEFAULT_SURGE_THRESHOLD_PERCENTAGE), oldImbalance, newImbalance),
                "Pool is surging"
            );
        }
    }

    function testComputeImbalancePeakLowerThanAlpha() public view {
        // Price peak = s/c = 1. Since price peak < alpha, the peak should be alpha.
        IGyroECLPPool.EclpParams memory eclpParamsOutsideInterval = IGyroECLPPool.EclpParams({
            alpha: 1.2e18,
            beta: 1.3e18,
            c: 707106781186547524,
            s: 707106781186547524,
            lambda: 1e18
        });

        // Derived params calculated offchain, using the jupyter notebook file on "pkg/pool-hooks/jupyter/SurgeECLP.ipynb"
        IGyroECLPPool.DerivedEclpParams memory derivedECLPParamsOutsideInterval = IGyroECLPPool.DerivedEclpParams({
            tauAlpha: IGyroECLPPool.Vector2({
                x: 9053574604251854335907431643208482816,
                y: 99589320646770395333798506640470704128
            }),
            tauBeta: IGyroECLPPool.Vector2({
                x: 12933918406776802937837365453075251200,
                y: 99160041118622168449730422792630829056
            }),
            u: 1940171901262474300964966904933384192,
            v: 99374680882696281891764464716550766592,
            w: -214639764074107649756402779120730112,
            z: 10993746505514327456280777830730563584,
            dSq: 99999999999999997748809823456034029568
        });

        uint256[] memory balancesAlpha = [uint256(1e18), uint256(0)].toMemoryArray();
        (int256 aAlpha, int256 bAlpha) = hookMock.computeOffsetFromBalances(
            balancesAlpha,
            eclpParamsOutsideInterval,
            derivedECLPParamsOutsideInterval
        );
        uint256 imbalanceAlpha = hookMock.computeImbalance(balancesAlpha, eclpParamsOutsideInterval, aAlpha, bAlpha);
        uint256 priceNearAlpha = hookMock.computePriceFromBalances(
            balancesAlpha,
            eclpParamsOutsideInterval,
            derivedECLPParamsOutsideInterval
        );

        // Since the balances are exactly at the peak, the imbalance should be 0.
        assertEq(imbalanceAlpha, 0, "Imbalance should be 0");
        assertEq(priceNearAlpha, uint256(eclpParamsOutsideInterval.alpha), "Price should be equal to alpha");

        uint256[] memory balancesBeta = [uint256(0), uint256(1e18)].toMemoryArray();
        (int256 aBeta, int256 bBeta) = hookMock.computeOffsetFromBalances(
            balancesBeta,
            eclpParamsOutsideInterval,
            derivedECLPParamsOutsideInterval
        );
        uint256 imbalanceBeta = hookMock.computeImbalance(balancesBeta, eclpParamsOutsideInterval, aBeta, bBeta);
        uint256 priceNearBeta = hookMock.computePriceFromBalances(
            balancesBeta,
            eclpParamsOutsideInterval,
            derivedECLPParamsOutsideInterval
        );

        // Since the balances are exactly at the fartherst point from the peak, the imbalance should be 1.
        assertApproxEqAbs(imbalanceBeta, 1e18, 1000, "Imbalance should be 1");
        assertApproxEqAbs(
            priceNearBeta,
            uint256(eclpParamsOutsideInterval.beta),
            1000,
            "Price should be equal to beta"
        );
    }

    function testComputeImbalancePeakGreaterThanBeta() public view {
        // Price peak = s/c = 1. Since price peak > beta, the peak should be beta.
        IGyroECLPPool.EclpParams memory eclpParamsOutsideInterval = IGyroECLPPool.EclpParams({
            alpha: 0.7e18,
            beta: 0.8e18,
            c: 707106781186547524,
            s: 707106781186547524,
            lambda: 1e18
        });

        // Derived params calculated offchain, using the jupyter notebook file on "pkg/pool-hooks/jupyter/SurgeECLP.ipynb"
        IGyroECLPPool.DerivedEclpParams memory derivedECLPParamsOutsideInterval = IGyroECLPPool.DerivedEclpParams({
            tauAlpha: IGyroECLPPool.Vector2({
                x: -17378533390904770869772025989076877312,
                y: 98478355881793685067092123894344056832
            }),
            tauBeta: IGyroECLPPool.Vector2({
                x: -11043152607484651417618851378248024064,
                y: 99388373467361900537501525361393926144
            }),
            u: 3167690391710059135780776946708774912,
            v: 98933364674577792802296824627868991488,
            w: 455008792784103898281933401938198528,
            z: -14210842999194712324287059401073754112,
            dSq: 99999999999999997748809823456034029568
        });

        uint256[] memory balancesAlpha = [uint256(1e18), uint256(0)].toMemoryArray();
        (int256 aAlpha, int256 bAlpha) = hookMock.computeOffsetFromBalances(
            balancesAlpha,
            eclpParamsOutsideInterval,
            derivedECLPParamsOutsideInterval
        );
        uint256 imbalanceAlpha = hookMock.computeImbalance(balancesAlpha, eclpParamsOutsideInterval, aAlpha, bAlpha);
        uint256 priceNearAlpha = hookMock.computePriceFromBalances(
            balancesAlpha,
            eclpParamsOutsideInterval,
            derivedECLPParamsOutsideInterval
        );

        // Since the balances are exactly at the fartherst point from the peak, the imbalance should be 1.
        assertEq(imbalanceAlpha, 1e18, "Imbalance should be 0");
        assertEq(priceNearAlpha, uint256(eclpParamsOutsideInterval.alpha), "Price should be equal to alpha");

        uint256[] memory balancesBeta = [uint256(0), uint256(1e18)].toMemoryArray();
        (int256 aBeta, int256 bBeta) = hookMock.computeOffsetFromBalances(
            balancesBeta,
            eclpParamsOutsideInterval,
            derivedECLPParamsOutsideInterval
        );

        uint256 imbalanceBeta = hookMock.computeImbalance(balancesBeta, eclpParamsOutsideInterval, aBeta, bBeta);
        uint256 priceNearBeta = hookMock.computePriceFromBalances(
            balancesBeta,
            eclpParamsOutsideInterval,
            derivedECLPParamsOutsideInterval
        );

        // Since the balances are exactly at the peak, the imbalance should be 0.
        assertApproxEqAbs(imbalanceBeta, 0, 1000, "Imbalance should be 1");
        assertApproxEqAbs(
            priceNearBeta,
            uint256(eclpParamsOutsideInterval.beta),
            1000,
            "Price should be equal to beta"
        );
    }

    function testGetDefaultSurgeThresholdPercentage() public view {
        assertEq(
            hookMock.getDefaultSurgeThresholdPercentage(),
            DEFAULT_SURGE_THRESHOLD_PERCENTAGE,
            "Default surge threshold percentage should be correct"
        );
    }

    function testGetDefaultMaxSurgeFeePercentage() public view {
        assertEq(
            hookMock.getDefaultMaxSurgeFeePercentage(),
            DEFAULT_MAX_SURGE_FEE_PERCENTAGE,
            "Default max surge fee percentage should be correct"
        );
    }

    function testSetMaxSurgeFeePercentageIsAuthenticated() public {
        vm.prank(alice);
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        hookMock.setMaxSurgeFeePercentage(address(pool), 10e16);
    }

    function testSetMaxSurgeFeePercentageInvalidPercentage() public {
        uint256 invalidPercentage = 101e16;

        vm.prank(admin);
        vm.expectRevert(ISurgeHookCommon.InvalidPercentage.selector);
        hookMock.setMaxSurgeFeePercentage(address(pool), invalidPercentage);
    }

    function testSetMaxSurgeFeePercentageWithGovernance() public {
        authorizer.grantRole(
            ECLPSurgeHook(address(hookMock)).getActionId(ISurgeHookCommon.setMaxSurgeFeePercentage.selector),
            admin
        );

        uint256 validPercentage = 25e16;

        vm.expectEmit();
        emit ISurgeHookCommon.MaxSurgeFeePercentageChanged(pool, validPercentage);

        vm.prank(admin);
        hookMock.setMaxSurgeFeePercentage(address(pool), validPercentage);

        assertEq(hookMock.getMaxSurgeFeePercentage(pool), validPercentage, "Percentage was not set");
    }

    function testSetMaxSurgeFeePercentageWithSwapFeeManager() public {
        _mockPoolRoleAccounts(alice);

        uint256 validPercentage = 25e16;

        vm.expectEmit();
        emit ISurgeHookCommon.MaxSurgeFeePercentageChanged(pool, validPercentage);

        vm.prank(alice);
        hookMock.setMaxSurgeFeePercentage(address(pool), validPercentage);

        assertEq(hookMock.getMaxSurgeFeePercentage(pool), validPercentage, "Percentage was not set");
    }

    function testSetSurgeThresholdPercentageIsAuthenticated() public {
        vm.prank(alice);
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        hookMock.setSurgeThresholdPercentage(address(pool), 10e16);
    }

    function testSetSurgeThresholdPercentageInvalidPercentage() public {
        uint256 invalidPercentage = 101e16;

        vm.prank(admin);
        vm.expectRevert(ISurgeHookCommon.InvalidPercentage.selector);
        hookMock.setSurgeThresholdPercentage(address(pool), invalidPercentage);
    }

    function testSetSurgeThresholdPercentageWithGovernance() public {
        authorizer.grantRole(
            ECLPSurgeHook(address(hookMock)).getActionId(ISurgeHookCommon.setSurgeThresholdPercentage.selector),
            admin
        );

        uint256 validPercentage = 25e16;

        vm.expectEmit();
        emit ISurgeHookCommon.ThresholdSurgePercentageChanged(pool, validPercentage);

        vm.prank(admin);
        hookMock.setSurgeThresholdPercentage(address(pool), validPercentage);

        assertEq(hookMock.getSurgeThresholdPercentage(pool), validPercentage, "Percentage was not set");
    }

    function testSetSurgeThresholdPercentageWithSwapFeeManager() public {
        _mockPoolRoleAccounts(alice);

        uint256 validPercentage = 25e16;

        vm.expectEmit();
        emit ISurgeHookCommon.ThresholdSurgePercentageChanged(pool, validPercentage);

        vm.prank(alice);
        hookMock.setSurgeThresholdPercentage(address(pool), validPercentage);

        assertEq(hookMock.getSurgeThresholdPercentage(pool), validPercentage, "Percentage was not set");
    }

    function testComputeSwapSurgeFeePercentageMaxLessThanStatic() public {
        authorizer.grantRole(
            ECLPSurgeHook(address(hookMock)).getActionId(ISurgeHookCommon.setMaxSurgeFeePercentage.selector),
            admin
        );

        uint256 staticSwapFeePercentage = vault.getStaticSwapFeePercentage(pool);

        vm.prank(admin);
        hookMock.setMaxSurgeFeePercentage(address(pool), staticSwapFeePercentage / 2);

        assertEq(
            hookMock.computeSwapSurgeFeePercentage(
                PoolSwapParams({
                    kind: SwapKind.EXACT_IN,
                    indexIn: 0,
                    indexOut: 1,
                    amountGivenScaled18: balancesScaled18[0] / 10,
                    balancesScaled18: balancesScaled18,
                    router: address(0),
                    userData: bytes("")
                }),
                pool,
                staticSwapFeePercentage
            ),
            staticSwapFeePercentage,
            "Surge fee is wrong"
        );
    }

    function testIsSurgingNewImbalanceZero() public view {
        assertFalse(hookMock.isSurging(uint64(DEFAULT_SURGE_THRESHOLD_PERCENTAGE), 90e16, 0), "Is surging");
    }

    function testPriceMonotonicity() public {
        uint256 NUM_SIMULATED_SWAPS = 50;

        uint256[] memory prices = new uint256[](NUM_SIMULATED_SWAPS);
        uint256 swapAmount = poolInitAmount / 20;

        // Execute series of swaps in one direction.
        for (uint i = 0; i < NUM_SIMULATED_SWAPS; i++) {
            prices[i] = hookMock.computePriceFromBalances(balancesScaled18, eclpParams, derivedECLPParams);

            // Simulate swap.
            balancesScaled18[1] += swapAmount;
            balancesScaled18[0] -= swapAmount.divDown(prices[i]); // Approximate based on price
        }

        // Verify monotonic price movement.
        for (uint i = 1; i < NUM_SIMULATED_SWAPS; i++) {
            assertGt(prices[i], prices[i - 1], "Price should increase monotonically");
        }
    }

    function testExtremeBalances() public view {
        // Test with maximum allowed balances (sum must be <= 1e34).
        uint256 maxTotalBalance = 1e34; // From GyroECLPMath library
        uint256[] memory largeBalances = [maxTotalBalance / 2, maxTotalBalance / 2].toMemoryArray();
        uint256 alpha = uint256(eclpParams.alpha);
        uint256 beta = uint256(eclpParams.beta);

        // Should not revert.
        uint256 price = hookMock.computePriceFromBalances(largeBalances, eclpParams, derivedECLPParams);

        // Price should be within bounds.
        assertGe(price, alpha, "Large balance price below alpha");
        assertLe(price, beta, "Large balance price above beta");

        // Test with asymmetric large balances.
        largeBalances = [maxTotalBalance / 10, (maxTotalBalance * 9) / 10].toMemoryArray();
        price = hookMock.computePriceFromBalances(largeBalances, eclpParams, derivedECLPParams);
        assertGe(price, alpha, "Asymmetric large balance price below alpha");
        assertLe(price, beta, "Asymmetric large balance price above beta");

        // Test with very small balances.
        uint256[] memory smallBalances = [uint256(1e6), uint256(1e6)].toMemoryArray();
        price = hookMock.computePriceFromBalances(smallBalances, eclpParams, derivedECLPParams);
        assertGe(price, alpha, "Small balance price below alpha");
        assertLe(price, beta, "Small balance price above beta");

        // Test with extreme price ratios at small scale.
        smallBalances = [uint256(1e6), uint256(1e12)].toMemoryArray();
        price = hookMock.computePriceFromBalances(smallBalances, eclpParams, derivedECLPParams);
        assertGe(price, alpha, "Extreme ratio small balance price below alpha");
        assertLe(price, beta, "Extreme ratio small balance price above beta");
    }

    function testIsSurgingSwapAtDifferentImbalanceLevels__Fuzz(uint256 swapAmountPercentage) public view {
        swapAmountPercentage = bound(swapAmountPercentage, 1e16, 20e16);

        uint256 staticSwapFee = vault.getStaticSwapFeePercentage(pool);

        // Calculate balances that should be at peak price (s/c ≈ 3759).
        uint256 peakPrice = uint256(eclpParams.s).divDown(uint256(eclpParams.c));

        uint256[] memory actualPeakBalances = new uint256[](2);
        actualPeakBalances[0] = FixedPoint.ONE; // 1 WETH
        actualPeakBalances[1] = peakPrice; // 3758 USDC (at peak price)

        // Test with balanced pool (at actual peak).
        uint256 smallSwapAmount = actualPeakBalances[0].mulDown(swapAmountPercentage);

        PoolSwapParams memory swapFromPeak = PoolSwapParams({
            kind: SwapKind.EXACT_IN,
            amountGivenScaled18: smallSwapAmount,
            balancesScaled18: actualPeakBalances,
            indexIn: 0, // Add WETH
            indexOut: 1, // Remove USDC
            router: address(router),
            userData: bytes("")
        });

        // From actual peak, this should worsen balance.
        bool isSurging = hookMock.isSurgingSwap(swapFromPeak, pool, staticSwapFee);

        // But it might not surge if the imbalance is still below threshold!
        // Check the actual imbalance:
        (uint256 amountCalculatedScaled18, , ) = hookMock.computeSwap(swapFromPeak, eclpParams, derivedECLPParams);

        uint256[] memory newBalances = new uint256[](2);
        newBalances[0] = actualPeakBalances[0] + smallSwapAmount;
        newBalances[1] = actualPeakBalances[1] - amountCalculatedScaled18;

        (int256 a, int256 b) = hookMock.computeOffsetFromBalances(actualPeakBalances, eclpParams, derivedECLPParams);
        //uint256 oldImbalance = hookMock.computeImbalance(actualPeakBalances, eclpParams, a, b);
        uint256 newImbalance = hookMock.computeImbalance(newBalances, eclpParams, a, b);

        // The swap worsens balance but might not exceed threshold.
        if (newImbalance > hookMock.getSurgeThresholdPercentage(pool)) {
            assertTrue(isSurging, "Should surge when moving away from peak above threshold");
        } else {
            assertFalse(isSurging, "Should not surge when below threshold");
        }
    }

    function _mockPoolRoleAccounts(address swapFeeManager) private {
        PoolRoleAccounts memory poolRoleAccounts = PoolRoleAccounts({
            pauseManager: address(0x01),
            swapFeeManager: swapFeeManager,
            poolCreator: address(0x01)
        });
        vm.mockCall(
            address(vault),
            abi.encodeWithSelector(IVaultExtension.getPoolRoleAccounts.selector, pool),
            abi.encode(poolRoleAccounts)
        );
    }
}
