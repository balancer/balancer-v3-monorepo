// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { IVaultMock } from "@balancer-labs/v3-interfaces/contracts/test/IVaultMock.sol";
import { IGyro2CLPPool } from "@balancer-labs/v3-interfaces/contracts/pool-gyro/IGyro2CLPPool.sol";
import { LiquidityManagement, PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { BaseContractsDeployer } from "@balancer-labs/v3-solidity-utils/test/foundry/utils/BaseContractsDeployer.sol";
import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { ProtocolFeeControllerMock } from "@balancer-labs/v3-vault/contracts/test/ProtocolFeeControllerMock.sol";

import { Gyro2CLPPoolFactory } from "../../../contracts/Gyro2CLPPoolFactory.sol";
import { Gyro2CLPPool } from "../../../contracts/Gyro2CLPPool.sol";
import { Gyro2CLPPoolMock } from "../../../contracts/test/Gyro2CLPPoolMock.sol";

contract Gyro2ClpPoolDeployer is BaseContractsDeployer {
    using CastingHelpers for address[];

    uint256 internal _sqrtAlpha = 997496867163000167; // alpha (lower price rate) = 0.995
    uint256 internal _sqrtBeta = 1002496882788171068; // beta (upper price rate) = 1.005
    uint256 internal DEFAULT_SWAP_FEE = 1e12; // 0.0001% swap fee, but can be overridden by the tests

    string private artifactsRootDir = "artifacts/";

    constructor() {
        // If this external artifact path exists, it means we are running outside of this repo.
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
    ) internal returns (address newPool, bytes memory poolArgs) {
        Gyro2CLPPoolFactory factory = deployGyro2CLPPoolFactory(vault);

        PoolRoleAccounts memory roleAccounts;

        newPool = factory.create(
            "Gyro 2-CLP Pool",
            "GRP",
            vault.buildTokenConfig(tokens.asIERC20(), rateProviders),
            _sqrtAlpha,
            _sqrtBeta,
            roleAccounts,
            DEFAULT_SWAP_FEE,
            address(0),
            bytes32("")
        );
        vm.label(newPool, label);

        // Cannot set the pool creator directly on a standard Balancer stable pool factory.
        vault.manualSetPoolCreator(newPool, poolCreator);

        ProtocolFeeControllerMock feeController = ProtocolFeeControllerMock(address(vault.getProtocolFeeController()));
        feeController.manualSetPoolCreator(newPool, poolCreator);

        poolArgs = abi.encode(
            IGyro2CLPPool.GyroParams({
                name: "Gyro 2CLP Pool",
                symbol: "GRP",
                sqrtAlpha: _sqrtAlpha,
                sqrtBeta: _sqrtBeta
            }),
            vault
        );
    }

    function createGyro2ClpPoolMock(
        address[] memory tokens,
        IRateProvider[] memory rateProviders,
        string memory label,
        IVaultMock vault,
        address poolCreator
    ) internal returns (address newPool, bytes memory poolArgs) {
        LiquidityManagement memory liquidityManagement;
        PoolRoleAccounts memory roleAccounts;
        roleAccounts.poolCreator = poolCreator;

        IGyro2CLPPool.GyroParams memory params = IGyro2CLPPool.GyroParams({
            name: "Gyro 2CLP Pool Mock",
            symbol: "GRP-Mock",
            sqrtAlpha: _sqrtAlpha,
            sqrtBeta: _sqrtBeta
        });

        if (reusingArtifacts) {
            newPool = address(
                deployCode(_computeGyro2CLPPathTest(type(Gyro2CLPPoolMock).name), abi.encode(params, vault))
            );
        } else {
            newPool = address(new Gyro2CLPPoolMock(params, vault));
        }

        vm.label(newPool, label);

        vault.registerPool(
            newPool,
            vault.buildTokenConfig(tokens.asIERC20(), rateProviders),
            DEFAULT_SWAP_FEE,
            0,
            false,
            roleAccounts,
            address(0),
            liquidityManagement
        );

        poolArgs = abi.encode(
            IGyro2CLPPool.GyroParams({
                name: "Gyro 2CLP Pool Mock",
                symbol: "GRP-Mock",
                sqrtAlpha: _sqrtAlpha,
                sqrtBeta: _sqrtBeta
            }),
            vault
        );
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

    function _computeGyro2CLPPathTest(string memory name) private view returns (string memory) {
        return string(abi.encodePacked(artifactsRootDir, "contracts/test/", name, ".sol/", name, ".json"));
    }
}
