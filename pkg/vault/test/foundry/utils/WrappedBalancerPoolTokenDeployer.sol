// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { BaseContractsDeployer } from "@balancer-labs/v3-solidity-utils/test/foundry/utils/BaseContractsDeployer.sol";

import { WrappedBalancerPoolToken } from "../../../contracts/WrappedBalancerPoolToken.sol";
import { WrappedBalancerPoolTokenFactory } from "../../../contracts/WrappedBalancerPoolTokenFactory.sol";

/**
 * @dev This contract contains functions for deploying mocks and contracts related to the "WrappedBalancerPoolToken".
 * These functions should have support for reusing artifacts from the hardhat compilation.
 */
contract WrappedBalancerPoolTokenContractsDeployer is BaseContractsDeployer {
    string private artifactsRootDir = "artifacts/";

    constructor() {
        // if this external artifact path exists, it means we are running outside of this repo
        if (vm.exists("artifacts/@balancer-labs/v3-oracles/")) {
            artifactsRootDir = "artifacts/@balancer-labs/v3-oracles/";
        }
    }

    function deployWrappedBalancerPoolTokenFactory(IVault vault) internal returns (WrappedBalancerPoolTokenFactory) {
        if (reusingArtifacts) {
            return
                WrappedBalancerPoolTokenFactory(
                    deployCode(
                        _computeWrappedBalancerPoolTokenPath(type(WrappedBalancerPoolTokenFactory).name),
                        abi.encode(vault)
                    )
                );
        } else {
            return new WrappedBalancerPoolTokenFactory(vault);
        }
    }

    function deployWrappedBalancerPoolToken(
        IVault vault,
        IERC20 balancerPoolToken,
        string memory name,
        string memory symbol
    ) internal returns (WrappedBalancerPoolToken) {
        if (reusingArtifacts) {
            return
                WrappedBalancerPoolToken(
                    deployCode(
                        _computeWrappedBalancerPoolTokenPath(type(WrappedBalancerPoolToken).name),
                        abi.encode(vault, balancerPoolToken, name, symbol)
                    )
                );
        } else {
            return new WrappedBalancerPoolToken(vault, balancerPoolToken, name, symbol);
        }
    }

    function _computeWrappedBalancerPoolTokenPath(string memory name) private view returns (string memory) {
        return string(abi.encodePacked(artifactsRootDir, "contracts/", name, ".sol/", name, ".json"));
    }

    function _computeWrappedBalancerPoolTokenPathTest(string memory name) private view returns (string memory) {
        return string(abi.encodePacked(artifactsRootDir, "contracts/test/", name, ".sol/", name, ".json"));
    }
}
