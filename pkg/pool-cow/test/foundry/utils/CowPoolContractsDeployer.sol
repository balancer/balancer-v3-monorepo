// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { BaseContractsDeployer } from "@balancer-labs/v3-solidity-utils/test/foundry/utils/BaseContractsDeployer.sol";

import { CowPoolFactory } from "../../../contracts/CowPoolFactory.sol";
import { CowRouter } from "../../../contracts/CowRouter.sol";
import { CowPool } from "../../../contracts/CowPool.sol";

/**
 * @dev This contract contains functions for deploying mocks and contracts related to the "Cow AMM Pool". These
 * functions should have support for reusing artifacts from the hardhat compilation.
 */
contract CowPoolContractsDeployer is BaseContractsDeployer {
    string private artifactsRootDir = "artifacts/";

    constructor() {
        // if this external artifact path exists, it means we are running outside of this repo
        if (vm.exists("artifacts/@balancer-labs/v3-pool-cow/")) {
            artifactsRootDir = "artifacts/@balancer-labs/v3-pool-cow/";
        }
    }

    function deployCowPoolFactory(
        IVault vault,
        uint32 pauseWindowDuration,
        string memory factoryVersion,
        string memory poolVersion,
        address trustedCowRouter
    ) internal returns (CowPoolFactory) {
        if (reusingArtifacts) {
            return
                CowPoolFactory(
                    deployCode(
                        _computeCowPath(type(CowPoolFactory).name),
                        abi.encode(vault, pauseWindowDuration, factoryVersion, poolVersion, trustedCowRouter)
                    )
                );
        } else {
            return new CowPoolFactory(vault, pauseWindowDuration, factoryVersion, poolVersion, trustedCowRouter);
        }
    }

    function deployCowPoolRouter(IVault vault, uint256 initialProtocolFeePercentage) internal returns (CowRouter) {
        if (reusingArtifacts) {
            return
                CowRouter(
                    deployCode(_computeCowPath(type(CowRouter).name), abi.encode(vault, initialProtocolFeePercentage))
                );
        } else {
            return new CowRouter(vault, initialProtocolFeePercentage);
        }
    }

    function _computeCowPath(string memory name) private view returns (string memory) {
        return string(abi.encodePacked(artifactsRootDir, "contracts/", name, ".sol/", name, ".json"));
    }

    function _computeCowPathTest(string memory name) private view returns (string memory) {
        return string(abi.encodePacked(artifactsRootDir, "contracts/test/", name, ".sol/", name, ".json"));
    }
}
