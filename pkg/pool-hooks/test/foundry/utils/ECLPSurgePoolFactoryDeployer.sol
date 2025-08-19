// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";

import { IGyroECLPPool } from "@balancer-labs/v3-interfaces/contracts/pool-gyro/IGyroECLPPool.sol";

import { BaseContractsDeployer } from "@balancer-labs/v3-solidity-utils/test/foundry/utils/BaseContractsDeployer.sol";

import { ECLPSurgeHook } from "../../../contracts/ECLPSurgeHook.sol";
import { ECLPSurgePoolFactory } from "../../../contracts/ECLPSurgePoolFactory.sol";

/**
 * @dev This contract contains functions for deploying mocks and contracts related to the "ECLPPool". These functions
 * should have support for reusing artifacts from the hardhat compilation.
 */
contract ECLPSurgePoolFactoryDeployer is BaseContractsDeployer {
    string private artifactsRootDir = "artifacts/";

    // Extracted from pool 0x2191df821c198600499aa1f0031b1a7514d7a7d9 on Mainnet.
    int256 internal _paramsAlpha = 998502246630054917;
    int256 internal _paramsBeta = 1000200040008001600;
    int256 internal _paramsC = 707106781186547524;
    int256 internal _paramsS = 707106781186547524;
    int256 internal _paramsLambda = 4000000000000000000000;

    int256 internal _tauAlphaX = -94861212813096057289512505574275160547;
    int256 internal _tauAlphaY = 31644119574235279926451292677567331630;
    int256 internal _tauBetaX = 37142269533113549537591131345643981951;
    int256 internal _tauBetaY = 92846388265400743995957747409218517601;
    int256 internal _u = 66001741173104803338721745994955553010;
    int256 internal _v = 62245253919818011890633399060291020887;
    int256 internal _w = 30601134345582732000058913853921008022;
    int256 internal _z = -28859471639991253843240999485797747790;
    int256 internal _dSq = 99999999999999999886624093342106115200;

    constructor() {
        // if this external artifact path exists, it means we are running outside of this repo
        if (vm.exists("artifacts/@balancer-labs/v3-pool-hooks/")) {
            artifactsRootDir = "artifacts/@balancer-labs/v3-pool-hooks/";
        }
    }

    function deployECLPSurgePoolFactory(
        ECLPSurgeHook eclpSurgeHook,
        uint32 pauseWindowDuration,
        string memory factoryVersion,
        string memory poolVersion
    ) internal returns (ECLPSurgePoolFactory) {
        if (reusingArtifacts) {
            return
                ECLPSurgePoolFactory(
                    deployCode(
                        "artifacts/contracts/ECLPSurgePoolFactory.sol/ECLPSurgePoolFactory.json",
                        abi.encode(eclpSurgeHook, pauseWindowDuration, factoryVersion, poolVersion)
                    )
                );
        } else {
            return new ECLPSurgePoolFactory(eclpSurgeHook, pauseWindowDuration, factoryVersion, poolVersion);
        }
    }

    function getECLPPoolParams()
        internal
        view
        returns (IGyroECLPPool.EclpParams memory eclpParams, IGyroECLPPool.DerivedEclpParams memory derivedEclpParams)
    {
        return (
            IGyroECLPPool.EclpParams({
                alpha: _paramsAlpha,
                beta: _paramsBeta,
                c: _paramsC,
                s: _paramsS,
                lambda: _paramsLambda
            }),
            IGyroECLPPool.DerivedEclpParams({
                tauAlpha: IGyroECLPPool.Vector2({ x: _tauAlphaX, y: _tauAlphaY }),
                tauBeta: IGyroECLPPool.Vector2({ x: _tauBetaX, y: _tauBetaY }),
                u: _u,
                v: _v,
                w: _w,
                z: _z,
                dSq: _dSq
            })
        );
    }
}
