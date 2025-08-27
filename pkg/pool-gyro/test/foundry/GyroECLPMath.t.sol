// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";

import { IGyroECLPPool } from "@balancer-labs/v3-interfaces/contracts/pool-gyro/IGyroECLPPool.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { GyroECLPMath } from "@balancer-labs/v3-pool-gyro/contracts/lib/GyroECLPMath.sol";

contract GyroECLPMathTest is Test {
    using ArrayHelpers for *;

    IGyroECLPPool.EclpParams private _eclpParams;
    IGyroECLPPool.DerivedEclpParams private _derivedECLPParams;
    uint256[] private _balancesScaled18;

    function setUp() public {
        _eclpParams = IGyroECLPPool.EclpParams({
            alpha: 3100000000000000000000,
            beta: 4400000000000000000000,
            c: 266047486094289,
            s: 999999964609366945,
            lambda: 20000000000000000000000
        });
        _derivedECLPParams = IGyroECLPPool.DerivedEclpParams({
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

        // Data from pool 0xf78556b9ccce5a6eb9476a4d086ea15f3790660a, Arbitrum.
        // Token A is WETH, and Token B is USDC.
        _balancesScaled18 = [uint256(2948989424059932952), uint256(9513574260000000000000)].toMemoryArray();
    }

    function testPriceComputation() public view {
        // Price computed offchain.
        uint256 expectedPrice = 3663201029819534758509;

        (int256 a, int256 b) = GyroECLPMath.computeOffsetFromBalances(
            _balancesScaled18,
            _eclpParams,
            _derivedECLPParams
        );
        uint256 actualPrice = GyroECLPMath.computePrice(_balancesScaled18, _eclpParams, a, b);
        assertEq(actualPrice, expectedPrice, "Prices do not match");
    }
}
