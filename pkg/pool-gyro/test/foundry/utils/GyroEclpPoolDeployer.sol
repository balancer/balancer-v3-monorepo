// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IGyroECLPPool } from "@balancer-labs/v3-interfaces/contracts/pool-gyro/IGyroECLPPool.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { IVaultMock } from "@balancer-labs/v3-interfaces/contracts/test/IVaultMock.sol";
import { PoolRoleAccounts, TokenConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { BaseContractsDeployer } from "@balancer-labs/v3-solidity-utils/test/foundry/utils/BaseContractsDeployer.sol";
import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";

import { ProtocolFeeControllerMock } from "@balancer-labs/v3-vault/contracts/test/ProtocolFeeControllerMock.sol";

import { GyroECLPPoolFactory } from "../../../contracts/GyroECLPPoolFactory.sol";
import { GyroECLPPool } from "../../../contracts/GyroECLPPool.sol";

contract GyroEclpPoolDeployer is BaseContractsDeployer {
    using CastingHelpers for address[];

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

    string private artifactsRootDir = "artifacts/";

    constructor() {
        // If this external artifact path exists, it means we are running outside of this repo.
        if (vm.exists("artifacts/@balancer-labs/v3-pool-gyro/")) {
            artifactsRootDir = "artifacts/@balancer-labs/v3-pool-gyro/";
        }
    }

    function createGyroEclpPool(
        address[] memory tokens,
        IRateProvider[] memory rateProviders,
        string memory label,
        IVaultMock vault,
        address poolCreator
    ) internal returns (address) {
        GyroECLPPoolFactory factory = deployGyroECLPPoolFactory(vault);

        PoolRoleAccounts memory roleAccounts;
        GyroECLPPool newPool;

        // Avoids Stack-too-deep.
        {
            IGyroECLPPool.EclpParams memory params = IGyroECLPPool.EclpParams({
                alpha: _paramsAlpha,
                beta: _paramsBeta,
                c: _paramsC,
                s: _paramsS,
                lambda: _paramsLambda
            });

            IGyroECLPPool.DerivedEclpParams memory derivedParams = IGyroECLPPool.DerivedEclpParams({
                tauAlpha: IGyroECLPPool.Vector2(_tauAlphaX, _tauAlphaY),
                tauBeta: IGyroECLPPool.Vector2(_tauBetaX, _tauBetaY),
                u: _u,
                v: _v,
                w: _w,
                z: _z,
                dSq: _dSq
            });

            TokenConfig[] memory tokenConfig = vault.buildTokenConfig(tokens.asIERC20(), rateProviders);

            newPool = GyroECLPPool(
                factory.create(
                    label,
                    label,
                    tokenConfig,
                    params,
                    derivedParams,
                    roleAccounts,
                    0,
                    address(0),
                    bytes32("")
                )
            );
        }
        vm.label(address(newPool), label);

        // Cannot set the pool creator directly on a standard Balancer stable pool factory.
        vault.manualSetPoolCreator(address(newPool), poolCreator);

        ProtocolFeeControllerMock feeController = ProtocolFeeControllerMock(address(vault.getProtocolFeeController()));
        feeController.manualSetPoolCreator(address(newPool), poolCreator);

        return address(newPool);
    }

    function deployGyroECLPPoolFactory(IVault vault) internal returns (GyroECLPPoolFactory) {
        if (reusingArtifacts) {
            return
                GyroECLPPoolFactory(
                    deployCode(_computeGyroECLPPath(type(GyroECLPPoolFactory).name), abi.encode(vault, 365 days))
                );
        } else {
            return new GyroECLPPoolFactory(vault, 365 days);
        }
    }

    function _computeGyroECLPPath(string memory name) private view returns (string memory) {
        return string(abi.encodePacked(artifactsRootDir, "contracts/", name, ".sol/", name, ".json"));
    }
}
