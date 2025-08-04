// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IGyroECLPPool } from "@balancer-labs/v3-interfaces/contracts/pool-gyro/IGyroECLPPool.sol";

import { PoolSwapParams, SwapKind } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";

import { ECLPSurgeHookMock } from "../../contracts/test/ECLPSurgeHookMock.sol";

contract ECLPSurgeHookUnitTest is BaseVaultTest {
    using ArrayHelpers for *;

    uint64 private constant _SURGE_THRESHOLD = 10e16; // 10%

    ECLPSurgeHookMock private hookMock;
    IGyroECLPPool.EclpParams private eclpParams;
    IGyroECLPPool.DerivedEclpParams private derivedECLPParams;
    uint256[] private balancesScaled18;

    function setUp() public override {
        super.setUp();

        // Data from pool 0xf78556b9ccce5a6eb9476a4d086ea15f3790660a, Arbitrum.
        // Token A is WETH, and Token B is USDC.
        hookMock = new ECLPSurgeHookMock(vault, 95e16, _SURGE_THRESHOLD, "1");
        balancesScaled18 = [uint256(2948989424059932952), uint256(9513574260000000000000)].toMemoryArray();
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

        // USDC in.
        uint256 amountGivenScaled18 = 100e18;

        PoolSwapParams memory request = PoolSwapParams({
            kind: SwapKind.EXACT_IN,
            amountGivenScaled18: 100e18,
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

        // USDC out.
        uint256 amountGivenScaled18 = 100e18;

        PoolSwapParams memory request = PoolSwapParams({
            kind: SwapKind.EXACT_OUT,
            amountGivenScaled18: 100e18,
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
}
