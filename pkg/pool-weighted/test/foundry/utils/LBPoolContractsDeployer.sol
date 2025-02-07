// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { BaseContractsDeployer } from "@balancer-labs/v3-solidity-utils/test/foundry/utils/BaseContractsDeployer.sol";

import { LBPoolFactory } from "../../../contracts/lbp/LBPoolFactory.sol";

/**
 * @dev This contract contains functions for deploying mocks and contracts related to the "WeightedPool". These functions should have support for reusing artifacts from the hardhat compilation.
 */
contract LBPoolContractsDeployer is BaseContractsDeployer {
    string private artifactsRootDir = "artifacts/";

    constructor() {
        // if this external artifact path exists, it means we are running outside of this repo
        if (vm.exists("artifacts/@balancer-labs/v3-pool-weighted/")) {
            artifactsRootDir = "artifacts/@balancer-labs/v3-pool-weighted/";
        }
    }

    function deployLBPoolFactory(
        IVault vault,
        uint32 pauseWindowDuration,
        string memory factoryVersion,
        string memory poolVersion,
        address router
    ) internal returns (LBPoolFactory) {
        if (reusingArtifacts) {
            return
                LBPoolFactory(
                    deployCode(
                        _computeLBPoolPath(type(LBPoolFactory).name),
                        abi.encode(vault, pauseWindowDuration, factoryVersion, poolVersion, router)
                    )
                );
        } else {
            return new LBPoolFactory(vault, pauseWindowDuration, factoryVersion, poolVersion, router);
        }
    }

    function _computeLBPoolPath(string memory name) private view returns (string memory) {
        return string(abi.encodePacked(artifactsRootDir, "contracts/lbp/", name, ".sol/", name, ".json"));
    }
}
