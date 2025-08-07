// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { BaseContractsDeployer } from "@balancer-labs/v3-solidity-utils/test/foundry/utils/BaseContractsDeployer.sol";

import { ECLPSurgeHook } from "../../../contracts/ECLPSurgeHook.sol";
import { ECLPSurgeHookMock } from "../../../contracts/test/ECLPSurgeHookMock.sol";
import { ECLPSurgePoolFactory } from "../../../contracts/ECLPSurgePoolFactory.sol";

/**
 * @dev This contract contains functions for deploying mocks and contracts related to the "ECLPSurgeHook".
 * These functions should have support for reusing artifacts from the hardhat compilation.
 */
contract ECLPSurgeHookDeployer is BaseContractsDeployer {
    uint256 public constant DEFAULT_SURGE_THRESHOLD_PERCENTAGE = 10e16; // 10%
    uint256 public constant DEFAULT_MAX_SURGE_FEE_PERCENTAGE = 95e16; // 95%

    string private artifactsRootDir = "artifacts/";

    constructor() {
        // if this external artifact path exists, it means we are running outside of this repo
        if (vm.exists("artifacts/@balancer-labs/v3-pool-hooks/")) {
            artifactsRootDir = "artifacts/@balancer-labs/v3-pool-hooks/";
        }
    }

    function deployECLPSurgeHook(
        IVault vault,
        uint256 defaultMaxSurgeFeePercentage,
        uint256 defaultSurgeThresholdPercentage,
        string memory version
    ) internal returns (ECLPSurgeHook) {
        if (reusingArtifacts) {
            return
                ECLPSurgeHook(
                    deployCode(
                        "artifacts/contracts/ECLPSurgeHook.sol/ECLPSurgeHook.json",
                        abi.encode(vault, defaultMaxSurgeFeePercentage, defaultSurgeThresholdPercentage, version)
                    )
                );
        } else {
            return new ECLPSurgeHook(vault, defaultMaxSurgeFeePercentage, defaultSurgeThresholdPercentage, version);
        }
    }

    function deployECLPSurgeHookMock(
        IVault vault,
        uint256 defaultMaxSurgeFeePercentage,
        uint256 defaultSurgeThresholdPercentage,
        string memory version
    ) internal returns (ECLPSurgeHookMock) {
        if (reusingArtifacts) {
            return
                ECLPSurgeHookMock(
                    deployCode(
                        "artifacts/contracts/test/ECLPSurgeHookMock.sol/ECLPSurgeHookMock.json",
                        abi.encode(vault, defaultMaxSurgeFeePercentage, defaultSurgeThresholdPercentage, version)
                    )
                );
        } else {
            return new ECLPSurgeHookMock(vault, defaultMaxSurgeFeePercentage, defaultSurgeThresholdPercentage, version);
        }
    }
}
