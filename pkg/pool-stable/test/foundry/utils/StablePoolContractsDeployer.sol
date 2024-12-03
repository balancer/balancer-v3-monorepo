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
    function deployStablePool(StablePool.NewPoolParams memory params, IVault vault) internal returns (StablePool) {
        if (reusingArtifacts) {
            return
                StablePool(deployCode("artifacts/contracts/StablePool.sol/StablePool.json", abi.encode(params, vault)));
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
                        "artifacts/contracts/StablePoolFactory.sol/StablePoolFactory.json",
                        abi.encode(vault, pauseWindowDuration, factoryVersion, poolVersion)
                    )
                );
        } else {
            return new StablePoolFactory(vault, pauseWindowDuration, factoryVersion, poolVersion);
        }
    }
}
