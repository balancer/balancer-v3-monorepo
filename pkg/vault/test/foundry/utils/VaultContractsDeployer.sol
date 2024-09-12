// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";

import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { BaseContractsDeployer } from "@balancer-labs/v3-solidity-utils/test/foundry/utils/BaseContractsDeployer.sol";

import { BaseHooksMock } from "../../../contracts/test/BaseHooksMock.sol";
import { BasicAuthorizerMock } from "../../../contracts/test/BasicAuthorizerMock.sol";
import { BatchRouterMock } from "../../../contracts/test/BatchRouterMock.sol";
import { ERC20MultiTokenMock } from "../../../contracts/test/ERC20MultiTokenMock.sol";

contract VaultContractsDeployer is BaseContractsDeployer {
    function deployBaseHookMock() internal returns (BaseHooksMock) {
        if (_reusingArtifacts()) {
            return BaseHooksMock(deployCode("artifacts/contracts/test/BaseHooksMock.sol/BaseHooksMock.json"));
        } else {
            return new BaseHooksMock();
        }
    }

    function deployBasicAuthorizerMock() internal returns (BasicAuthorizerMock) {
        if (_reusingArtifacts()) {
            return
                BasicAuthorizerMock(
                    deployCode("artifacts/contracts/test/BasicAuthorizerMock.sol/BasicAuthorizerMock.json")
                );
        } else {
            return new BasicAuthorizerMock();
        }
    }

    function deployBatchRouterMock(IVault vault, IWETH weth, IPermit2 permit2) internal returns (BatchRouterMock) {
        if (_reusingArtifacts()) {
            return
                BatchRouterMock(
                    payable(
                        deployCode(
                            "artifacts/contracts/test/BatchRouterMock.sol/BatchRouterMock.json",
                            abi.encode(vault, weth, permit2)
                        )
                    )
                );
        } else {
            return new BatchRouterMock(vault, weth, permit2);
        }
    }

    function deployERC20MultiTokenMock() internal returns (ERC20MultiTokenMock) {
        if (_reusingArtifacts()) {
            return
                ERC20MultiTokenMock(
                    deployCode("artifacts/contracts/test/ERC20MultiTokenMock.sol/ERC20MultiTokenMock.json")
                );
        } else {
            return new ERC20MultiTokenMock();
        }
    }
}
