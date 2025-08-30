// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IGyroECLPPool } from "@balancer-labs/v3-interfaces/contracts/pool-gyro/IGyroECLPPool.sol";

import { GyroECLPPool } from "@balancer-labs/v3-pool-gyro/contracts/GyroECLPPool.sol";

import { ECLPSurgeHookBaseTest } from "./ECLPSurgeHookBase.t.sol";

contract ECLPSurgeHookTest is ECLPSurgeHookBaseTest {
    function _setupEclpParams()
        internal
        pure
        override
        returns (IGyroECLPPool.EclpParams memory eclpParams, IGyroECLPPool.DerivedEclpParams memory derivedECLPParams)
    {
        // The pool has a price interval of [1.5, 2]. The peak price is around 1.73,
        // so s/c must be 1.73 and s^2 + c^2 = 1. Lambda was chosen arbitrarily.
        eclpParams = IGyroECLPPool.EclpParams({
            alpha: 1.5e18,
            beta: 2e18,
            c: 0.5e18,
            s: 0.866025403784439000e18,
            lambda: 5000000000000000000
        });

        // Derived params calculated offchain based on the params above, using the jupyter notebook file on
        // "pkg/pool-hooks/jupyter/SurgeECLP.ipynb".
        derivedECLPParams = IGyroECLPPool.DerivedEclpParams({
            tauAlpha: IGyroECLPPool.Vector2({
                x: -30690318166048988038075742958735327232,
                y: 95174074047855558443958259070940479488
            }),
            tauBeta: IGyroECLPPool.Vector2({
                x: 28744935033874503200864052705113407488,
                y: 95779583993136743138661466794178379776
            }),
            u: 25736219575747051354722245276237561856,
            v: 95628206506816527245215873647337537536,
            w: 262193497428812948762834278931234816,
            z: -15831504866068140020764829108410515456,
            dSq: 100000000000000054417207617891776593920
        });
    }

    function _getWethRate() internal pure override returns (uint256) {
        return 1e18;
    }

    function _balancePool()
        internal
        override
        returns (uint256[] memory initialBalancesRaw, uint256[] memory initialBalancesScaled18)
    {
        // Balances computed so that imbalance is close to 0 (0.00004%).
        initialBalancesRaw = new uint256[](2);
        initialBalancesRaw[wethIdx] = 200e18;
        initialBalancesRaw[usdcIdx] = 382.6e18;
        vault.manualSetPoolBalances(pool, initialBalancesRaw, initialBalancesRaw);

        uint256 imbalance = eclpSurgeHookMock.computeImbalanceFromBalances(GyroECLPPool(pool), initialBalancesRaw);
        assertLt(imbalance, 3e12, "Imbalance should be less than 0.0003%");

        // No rate providers and 18 decimals, so raw and scaled18 are the same.
        return (initialBalancesRaw, initialBalancesRaw);
    }
}
