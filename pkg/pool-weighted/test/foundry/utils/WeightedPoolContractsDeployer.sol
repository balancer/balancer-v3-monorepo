// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { BaseContractsDeployer } from "@balancer-labs/v3-solidity-utils/test/foundry/utils/BaseContractsDeployer.sol";

import { WeightedPoolMock } from "../../../contracts/test/WeightedPoolMock.sol";
import { WeightedMathMock } from "../../../contracts/test/WeightedMathMock.sol";
import { WeightedBasePoolMathMock } from "../../../contracts/test/WeightedBasePoolMathMock.sol";
import { WeightedPool } from "../../../contracts/WeightedPool.sol";
import { WeightedPoolFactory } from "../../../contracts/WeightedPoolFactory.sol";
import { WeightedPool8020Factory } from "../../../contracts/WeightedPool8020Factory.sol";

/**
 * @dev This contract contains functions for deploying mocks and contracts related to the "WeightedPool". These functions should have support for reusing artifacts from the hardhat compilation.
 */
contract WeightedPoolContractsDeployer is BaseContractsDeployer {
    string private artifactsRootDir = "artifacts/";

    constructor() {
        // if this external artifact path exists, it means we are running outside of this repo
        if (vm.exists("artifacts/@balancer-labs/v3-pool-weighted/")) {
            artifactsRootDir = "artifacts/@balancer-labs/v3-pool-weighted/";
        }
    }

    function deployWeightedPoolFactory(
        IVault vault,
        uint32 pauseWindowDuration,
        string memory factoryVersion,
        string memory poolVersion
    ) internal returns (WeightedPoolFactory) {
        if (reusingArtifacts) {
            return
                WeightedPoolFactory(
                    deployCode(
                        _computeWeightedPath(type(WeightedPoolFactory).name),
                        abi.encode(vault, pauseWindowDuration, factoryVersion, poolVersion)
                    )
                );
        } else {
            return new WeightedPoolFactory(vault, pauseWindowDuration, factoryVersion, poolVersion);
        }
    }

    function deployWeightedPool8020Factory(
        IVault vault,
        uint32 pauseWindowDuration,
        string memory factoryVersion,
        string memory poolVersion
    ) internal returns (WeightedPool8020Factory) {
        if (reusingArtifacts) {
            return
                WeightedPool8020Factory(
                    deployCode(
                        _computeWeightedPath(type(WeightedPool8020Factory).name),
                        abi.encode(vault, pauseWindowDuration, factoryVersion, poolVersion)
                    )
                );
        } else {
            return new WeightedPool8020Factory(vault, pauseWindowDuration, factoryVersion, poolVersion);
        }
    }

    function deployWeightedPoolMock(
        WeightedPool.NewPoolParams memory params,
        IVault vault
    ) internal returns (WeightedPoolMock) {
        if (reusingArtifacts) {
            return
                WeightedPoolMock(
                    deployCode(_computeWeightedPathTest(type(WeightedPoolMock).name), abi.encode(params, vault))
                );
        } else {
            return new WeightedPoolMock(params, vault);
        }
    }

    function deployWeightedMathMock() internal returns (WeightedMathMock) {
        if (reusingArtifacts) {
            return WeightedMathMock(deployCode(_computeWeightedPathTest(type(WeightedMathMock).name), ""));
        } else {
            return new WeightedMathMock();
        }
    }

    function deployWeightedBasePoolMathMock(uint256[] memory weights) internal returns (WeightedBasePoolMathMock) {
        if (reusingArtifacts) {
            return
                WeightedBasePoolMathMock(
                    deployCode(_computeWeightedPathTest(type(WeightedBasePoolMathMock).name), abi.encode(weights))
                );
        } else {
            return new WeightedBasePoolMathMock(weights);
        }
    }

    function _computeWeightedPath(string memory name) private view returns (string memory) {
        return string(abi.encodePacked(artifactsRootDir, "contracts/", name, ".sol/", name, ".json"));
    }

    function _computeWeightedPathTest(string memory name) private view returns (string memory) {
        return string(abi.encodePacked(artifactsRootDir, "contracts/test/", name, ".sol/", name, ".json"));
    }
}
