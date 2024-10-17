// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { IVaultMock } from "@balancer-labs/v3-interfaces/contracts/test/IVaultMock.sol";

import { BaseContractsDeployer } from "@balancer-labs/v3-solidity-utils/test/foundry/utils/BaseContractsDeployer.sol";
import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";

import { ProtocolFeeControllerMock } from "@balancer-labs/v3-vault/contracts/test/ProtocolFeeControllerMock.sol";

import { Gyro2CLPPoolFactory } from "../../../contracts/Gyro2CLPPoolFactory.sol";
import { Gyro2CLPPool } from "../../../contracts/Gyro2CLPPool.sol";

contract Gyro2ClpPoolDeployer is BaseContractsDeployer {
    using CastingHelpers for address[];

    uint256 private _sqrtAlpha = 997496867163000167; // alpha (lower price rate) = 0.995
    uint256 private _sqrtBeta = 1002496882788171068; // beta (upper price rate) = 1.005

    string private artifactsRootDir = "artifacts/";

    constructor() {
        // if this external artifact path exists, it means we are running outside of this repo
        if (vm.exists("artifacts/@balancer-labs/v3-pool-gyro/")) {
            artifactsRootDir = "artifacts/@balancer-labs/v3-pool-gyro/";
        }
    }

    function createGyro2ClpPool(
        address[] memory tokens,
        IRateProvider[] memory rateProviders,
        string memory label,
        IVaultMock vault,
        address poolCreator
    ) internal returns (address) {
        Gyro2CLPPoolFactory factory = deployGyro2CLPPoolFactory(vault);

        PoolRoleAccounts memory roleAccounts;

        Gyro2CLPPool newPool = Gyro2CLPPool(
            factory.create(
                "Gyro 2CLP Pool",
                "GRP",
                vault.buildTokenConfig(tokens.asIERC20(), rateProviders),
                _sqrtAlpha,
                _sqrtBeta,
                roleAccounts,
                0,
                address(0),
                bytes32("")
            )
        );
        vm.label(address(newPool), label);

        // Cannot set the pool creator directly on a standard Balancer stable pool factory.
        vault.manualSetPoolCreator(address(newPool), poolCreator);

        ProtocolFeeControllerMock feeController = ProtocolFeeControllerMock(address(vault.getProtocolFeeController()));
        feeController.manualSetPoolCreator(address(newPool), poolCreator);

        return address(newPool);
    }

    function deployGyro2CLPPoolFactory(IVault vault) internal returns (Gyro2CLPPoolFactory) {
        if (reusingArtifacts) {
            return
                Gyro2CLPPoolFactory(
                    deployCode(_computeGyro2CLPPath(type(Gyro2CLPPoolFactory).name), abi.encode(vault, 365 days))
                );
        } else {
            return new Gyro2CLPPoolFactory(vault, 365 days);
        }
    }

    function _computeGyro2CLPPath(string memory name) private view returns (string memory) {
        return string(abi.encodePacked(artifactsRootDir, "contracts/", name, ".sol/", name, ".json"));
    }
}
