// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { BaseContractsDeployer } from "@balancer-labs/v3-solidity-utils/test/foundry/utils/BaseContractsDeployer.sol";

import { StableSurgeHook } from "../../../contracts/StableSurgeHook.sol";
import { StableSurgeHookMock } from "../../../contracts/test/StableSurgeHookMock.sol";
import { StableSurgePoolFactory } from "../../../contracts/StableSurgePoolFactory.sol";

/**
 * @dev This contract contains functions for deploying mocks and contracts related to the "StableSurgeHook".
 * These functions should have support for reusing artifacts from the hardhat compilation.
 */
contract StableSurgeHookDeployer is BaseContractsDeployer {
    uint256 public constant DEFAULT_SURGE_THRESHOLD_PERCENTAGE = 30e16; // 30%
    uint256 public constant DEFAULT_MAX_SURGE_FEE_PERCENTAGE = 95e16; // 95%

    string private artifactsRootDir = "artifacts/";

    constructor() {
        // if this external artifact path exists, it means we are running outside of this repo
        if (vm.exists("artifacts/@balancer-labs/v3-pool-hooks/")) {
            artifactsRootDir = "artifacts/@balancer-labs/v3-pool-hooks/";
        }
    }

    function deployStableSurgeHook(
        IVault vault,
        uint256 defaultMaxSurgeFeePercentage,
        uint256 defaultSurgeThresholdPercentage,
        string memory version
    ) internal returns (StableSurgeHook) {
        if (reusingArtifacts) {
            return
                StableSurgeHook(
                    deployCode(
                        "artifacts/contracts/StableSurgeHook.sol/StableSurgeHook.json",
                        abi.encode(vault, defaultMaxSurgeFeePercentage, defaultSurgeThresholdPercentage, version)
                    )
                );
        } else {
            return new StableSurgeHook(vault, defaultMaxSurgeFeePercentage, defaultSurgeThresholdPercentage, version);
        }
    }

    function deployStableSurgeHookMock(
        IVault vault,
        uint256 defaultMaxSurgeFeePercentage,
        uint256 defaultSurgeThresholdPercentage,
        string memory version
    ) internal returns (StableSurgeHookMock) {
        if (reusingArtifacts) {
            return
                StableSurgeHookMock(
                    deployCode(
                        "artifacts/contracts/test/StableSurgeHookMock.sol/StableSurgeHookMock.json",
                        abi.encode(vault, defaultMaxSurgeFeePercentage, defaultSurgeThresholdPercentage, version)
                    )
                );
        } else {
            return
                new StableSurgeHookMock(vault, defaultMaxSurgeFeePercentage, defaultSurgeThresholdPercentage, version);
        }
    }
}
