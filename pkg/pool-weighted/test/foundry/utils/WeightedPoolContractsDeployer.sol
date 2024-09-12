// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { BaseContractsDeployer } from "@balancer-labs/v3-solidity-utils/test/foundry/utils/BaseContractsDeployer.sol";

import { WeightedPoolMock } from "../../../contracts/test//WeightedPoolMock.sol";
import { WeightedMathMock } from "../../../contracts/test//WeightedMathMock.sol";
import { WeightedBasePoolMathMock } from "../../../contracts/test/WeightedBasePoolMathMock.sol";
import { WeightedPool } from "../../../contracts/WeightedPool.sol";

contract WeightedPoolContractsDeployer is BaseContractsDeployer {
    function deployWeightedPoolMock(
        WeightedPool.NewPoolParams memory params,
        IVault vault
    ) internal returns (WeightedPoolMock) {
        if (_reusingArtifacts()) {
            return
                WeightedPoolMock(
                    deployCode(
                        "artifacts/contracts/test/WeightedPoolMock.sol/WeightedPoolMock.json",
                        abi.encode(params, vault)
                    )
                );
        } else {
            return new WeightedPoolMock(params, vault);
        }
    }

    function deployWeightedMathMock() internal returns (WeightedMathMock) {
        if (_reusingArtifacts()) {
            return
                WeightedMathMock(deployCode("artifacts/contracts/test/WeightedMathMock.sol/WeightedMathMock.json", ""));
        } else {
            return new WeightedMathMock();
        }
    }

    function deployWeightedBasePoolMathMock(uint256[] memory weights) internal returns (WeightedBasePoolMathMock) {
        if (_reusingArtifacts()) {
            return
                WeightedBasePoolMathMock(
                    deployCode(
                        "artifacts/contracts/test/WeightedBasePoolMathMock.sol/WeightedBasePoolMathMock.json",
                        abi.encode(weights)
                    )
                );
        } else {
            return new WeightedBasePoolMathMock(weights);
        }
    }
}
