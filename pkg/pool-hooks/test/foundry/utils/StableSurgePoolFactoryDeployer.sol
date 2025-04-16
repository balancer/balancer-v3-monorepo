// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { BaseContractsDeployer } from "@balancer-labs/v3-solidity-utils/test/foundry/utils/BaseContractsDeployer.sol";

import { StableSurgeHook } from "../../../contracts/StableSurgeHook.sol";
import { StableSurgePoolFactory } from "../../../contracts/StableSurgePoolFactory.sol";

/**
 * @dev This contract contains functions for deploying mocks and contracts related to the "StablePool". These functions should have support for reusing artifacts from the hardhat compilation.
 */
contract StableSurgePoolFactoryDeployer is BaseContractsDeployer {
    string private artifactsRootDir = "artifacts/";

    constructor() {
        // if this external artifact path exists, it means we are running outside of this repo
        if (vm.exists("artifacts/@balancer-labs/v3-pool-hooks/")) {
            artifactsRootDir = "artifacts/@balancer-labs/v3-pool-hooks/";
        }
    }

    function deployStableSurgePoolFactory(
        StableSurgeHook stableSurgeHook,
        uint32 pauseWindowDuration,
        string memory factoryVersion,
        string memory poolVersion
    ) internal returns (StableSurgePoolFactory) {
        if (reusingArtifacts) {
            return
                StableSurgePoolFactory(
                    deployCode(
                        "artifacts/contracts/StableSurgePoolFactory.sol/StableSurgePoolFactory.json",
                        abi.encode(stableSurgeHook, pauseWindowDuration, factoryVersion, poolVersion)
                    )
                );
        } else {
            return new StableSurgePoolFactory(stableSurgeHook, pauseWindowDuration, factoryVersion, poolVersion);
        }
    }
}
