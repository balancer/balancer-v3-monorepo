// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { BaseContractsDeployer } from "@balancer-labs/v3-solidity-utils/test/foundry/utils/BaseContractsDeployer.sol";

import { StablePoolFactory } from "../../../contracts/StablePoolFactory.sol";
import { StablePool } from "../../../contracts/StablePool.sol";

/**
 * @dev This contract contains functions for deploying mocks and contracts related to the "StablePool". These functions should have support for reusing artifacts from the hardhat compilation.
 */
contract StablePoolContractsDeployer is BaseContractsDeployer {
    string private artifactsRootDir = "artifacts/";

    constructor() {
        // if this external artifact path exists, it means we are running outside of this repo
        if (vm.exists("artifacts/@balancer-labs/v3-pool-stable/")) {
            artifactsRootDir = "artifacts/@balancer-labs/v3-pool-stable/";
        }
    }

    function deployStablePool(StablePool.NewPoolParams memory params, IVault vault) internal returns (StablePool) {
        if (reusingArtifacts) {
            return StablePool(deployCode(_computeStablePoolPath("StablePool"), abi.encode(params, vault)));
        } else {
            return new StablePool(params, vault);
        }
    }

    function deployStablePoolFactory(
        IVault vault,
        uint32 pauseWindowDuration,
        string memory factoryVersion,
        string memory poolVersion
    ) internal returns (StablePoolFactory) {
        if (reusingArtifacts) {
            return
                StablePoolFactory(
                    deployCode(
                        _computeStablePoolPath("StablePoolFactory"),
                        abi.encode(vault, pauseWindowDuration, factoryVersion, poolVersion)
                    )
                );
        } else {
            return new StablePoolFactory(vault, pauseWindowDuration, factoryVersion, poolVersion);
        }
    }

    function _computeStablePoolPath(string memory name) private view returns (string memory) {
        return string(abi.encodePacked(artifactsRootDir, "contracts/", name, ".sol/", name, ".json"));
    }
}
