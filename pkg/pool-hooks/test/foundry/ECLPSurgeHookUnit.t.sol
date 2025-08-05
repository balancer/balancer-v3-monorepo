// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IGyroECLPPool } from "@balancer-labs/v3-interfaces/contracts/pool-gyro/IGyroECLPPool.sol";

import { PoolSwapParams, SwapKind } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { ECLPSurgeHookMock } from "../../contracts/test/ECLPSurgeHookMock.sol";

contract ECLPSurgeHookUnitTest is BaseVaultTest {
    using FixedPoint for uint256;
    using ArrayHelpers for *;

    uint64 private constant _SURGE_THRESHOLD = 10e16; // 10%

    ECLPSurgeHookMock private hookMock;
    IGyroECLPPool.EclpParams private eclpParams;
    IGyroECLPPool.DerivedEclpParams private derivedECLPParams;
    uint256[] private balancesScaled18;
    uint256[] private peakBalancesScaled18;

    function setUp() public override {
        super.setUp();

        // Data from pool 0xf78556b9ccce5a6eb9476a4d086ea15f3790660a, Arbitrum.
        // Token A is WETH, and Token B is USDC.
        hookMock = new ECLPSurgeHookMock(vault, 95e16, _SURGE_THRESHOLD, "1");
        balancesScaled18 = [uint256(2948989424059932952), uint256(9513574260000000000000)].toMemoryArray();
        peakBalancesScaled18 = [uint256(2372852587012056561), uint256(11651374260000000000000)].toMemoryArray();
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
        assertGt(newImbalance, _SURGE_THRESHOLD, "New imbalance < Surge Threshold");
        assertFalse(hookMock.isSurging(_SURGE_THRESHOLD, oldImbalance, newImbalance), "Pool is surging");
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
        assertGt(newImbalance, _SURGE_THRESHOLD, "New imbalance < Surge Threshold");
        assertTrue(hookMock.isSurging(_SURGE_THRESHOLD, oldImbalance, newImbalance), "Pool is not surging");
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
            if (newImbalance > _SURGE_THRESHOLD) {
                assertTrue(hookMock.isSurging(_SURGE_THRESHOLD, oldImbalance, newImbalance), "Pool is not surging");
            } else {
                assertFalse(hookMock.isSurging(_SURGE_THRESHOLD, oldImbalance, newImbalance), "Pool is surging");
            }
        } else {
            assertFalse(hookMock.isSurging(_SURGE_THRESHOLD, oldImbalance, newImbalance), "Pool is surging");
        }
    }

    function testComputeImbalance__PeakLowerThanAlpha() public view {
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

    function testComputeImbalance__PeakGreaterThanBeta() public view {
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
}
