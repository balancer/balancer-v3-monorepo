// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IGyroECLPPool } from "@balancer-labs/v3-interfaces/contracts/pool-gyro/IGyroECLPPool.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { GyroECLPPool } from "@balancer-labs/v3-pool-gyro/contracts/GyroECLPPool.sol";

import { ECLPSurgeHookBaseTest } from "./ECLPSurgeHookBase.t.sol";

contract ECLPSurgeHookRateProviderTest is ECLPSurgeHookBaseTest {
    using FixedPoint for uint256;

    uint256 private constant _WETH_RATE = 3758e18;

    function _setupEclpParams()
        internal
        pure
        override
        returns (IGyroECLPPool.EclpParams memory eclpParams, IGyroECLPPool.DerivedEclpParams memory derivedECLPParams)
    {
        // Exactly the same pool as the ECLPSurgeHook test, but now with rate provider.
        // Price interval from [3100, 4400], but since the rate is 3758, alpha and beta are [3100/3758, 4400/3758].
        // With rate provider, peak price is 1, so s/c = 1 and s^2 + c^2 = 1. Lambda was chosen arbitrarily.
        eclpParams = IGyroECLPPool.EclpParams({
            alpha: 0.8249e18,
            beta: 1.1708e18,
            c: 0.707106781186547524e18,
            s: 0.707106781186547524e18,
            lambda: 1e18
        });

        // Derived params calculated offchain based on the params above, using the jupyter notebook file on
        // "pkg/pool-hooks/jupyter/SurgeECLP.ipynb".
        derivedECLPParams = IGyroECLPPool.DerivedEclpParams({
            tauAlpha: IGyroECLPPool.Vector2({
                x: -9551180604048044820490078158141259776,
                y: 99542829722028973980238505524940767232
            }),
            tauBeta: IGyroECLPPool.Vector2({
                x: 7843825351503711405832602479428108288,
                y: 99691897383163033790581971173395922944
            }),
            u: 8697502977775877522865529960079032320,
            v: 99617363552596003885410238349168345088,
            w: 74533830567032044994045374535565312,
            z: -853677626272166854902690429032988672,
            dSq: 99999999999999997748809823456034029568
        });
    }

    function _getWethRate() internal pure override returns (uint256) {
        return _WETH_RATE;
    }

    function _balancePool()
        internal
        override
        returns (uint256[] memory initialBalancesRaw, uint256[] memory initialBalancesScaled18)
    {
        // Balances computed so that imbalance is close to 0 (0.0004%).
        initialBalancesScaled18 = new uint256[](2);
        initialBalancesScaled18[wethIdx] = 414.32e18;
        initialBalancesScaled18[usdcIdx] = 500e18;

        initialBalancesRaw = new uint256[](2);
        initialBalancesRaw[wethIdx] = initialBalancesScaled18[wethIdx].divDown(_WETH_RATE);
        initialBalancesRaw[usdcIdx] = initialBalancesScaled18[usdcIdx];

        vault.manualSetPoolBalances(pool, initialBalancesRaw, initialBalancesScaled18);

        uint256 imbalance = eclpSurgeHookMock.computeImbalanceFromBalances(GyroECLPPool(pool), initialBalancesScaled18);
        assertLt(imbalance, 4e12, "Imbalance should be less than 0.0004%");
    }
}
