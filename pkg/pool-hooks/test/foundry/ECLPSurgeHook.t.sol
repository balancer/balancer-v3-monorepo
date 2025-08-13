// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { IGyroECLPPool } from "@balancer-labs/v3-interfaces/contracts/pool-gyro/IGyroECLPPool.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { ECLPSurgeHook } from "../../contracts/ECLPSurgeHook.sol";
import { ECLPSurgeHookBaseTest } from "./ECLPSurgeHookBase.t.sol";

contract ECLPSurgeHookTest is ECLPSurgeHookBaseTest {
    using FixedPoint for uint256;

    function _setupEclpParams()
        internal
        pure
        override
        returns (IGyroECLPPool.EclpParams memory eclpParams, IGyroECLPPool.DerivedEclpParams memory derivedECLPParams)
    {
        // The pool below is a WETH/USDC pool, with price interval from [3100, 4400]. The peak price is around 3758,
        // so s/c must be 3758 and s^2 + c^2 = 1. Lambda was chosen arbitrarily.
        eclpParams = IGyroECLPPool.EclpParams({
            alpha: 3100000000000000000000,
            beta: 4400000000000000000000,
            c: 266047486094289,
            s: 999999964609366945,
            lambda: 20000000000000000000000
        });

        // Derived params calculated offchain based on the params above, using the jupyter notebook file on
        // "pkg/pool-hooks/jupyter/SurgeECLP.ipynb".
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

    function _getWethRate() internal pure override returns (uint256) {
        return 1e18;
    }

    function _balancePool()
        internal
        override
        returns (uint256[] memory initialBalancesRaw, uint256[] memory initialBalancesScaled18)
    {
        // Balances computed so that imbalance is close to 0 (0.64%).
        initialBalancesRaw = new uint256[](2);
        initialBalancesRaw[wethIdx] = 0.1e18;
        initialBalancesRaw[usdcIdx] = 500e18;
        vault.manualSetPoolBalances(pool, initialBalancesRaw, initialBalancesRaw);

        // No rate providers and 18 decimals, so raw and scaled18 are the same.
        return (initialBalancesRaw, initialBalancesRaw);
    }
}
