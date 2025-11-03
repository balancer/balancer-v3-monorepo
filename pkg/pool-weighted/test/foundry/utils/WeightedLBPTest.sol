// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { LBPParams } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPool.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPCommon.sol";

import { LBPoolFactory } from "../../../contracts/lbp/LBPoolFactory.sol";
import { LBPoolContractsDeployer } from "./LBPoolContractsDeployer.sol";
import { BaseLBPTest } from "./BaseLBPTest.sol";

abstract contract WeightedLBPTest is BaseLBPTest, LBPoolContractsDeployer {
    uint256 internal constant HIGH_WEIGHT = uint256(70e16);
    uint256 internal constant LOW_WEIGHT = uint256(30e16);
    uint256 internal constant DEFAULT_WEIGHT = uint256(50e16);

    LBPoolFactory internal lbPoolFactory;

    uint256[] internal startWeights;
    uint256[] internal endWeights;

    function setUp() public virtual override {
        super.setUp();
    }

    function onAfterDeployMainContracts() internal override {
        super.onAfterDeployMainContracts();

        startWeights = new uint256[](2);
        startWeights[projectIdx] = HIGH_WEIGHT;
        startWeights[reserveIdx] = LOW_WEIGHT;

        endWeights = new uint256[](2);
        endWeights[projectIdx] = LOW_WEIGHT;
        endWeights[reserveIdx] = HIGH_WEIGHT;
    }

    function createPoolFactory() internal virtual override returns (address) {
        lbPoolFactory = deployLBPoolFactory(
            IVault(address(vault)),
            365 days,
            factoryVersion,
            poolVersion,
            address(router),
            address(migrationRouter)
        );
        vm.label(address(lbPoolFactory), "LB pool factory");

        return address(lbPoolFactory);
    }

    // Implement the virtual functions from BaseLBPTest
    function _createLBPool(
        address poolCreator,
        uint32 startTime,
        uint32 endTime,
        bool blockProjectTokenSwapsIn
    ) internal virtual override returns (address newPool, bytes memory poolArgs) {
        return
            _createLBPoolWithCustomWeights(
                poolCreator,
                startWeights[projectIdx],
                startWeights[reserveIdx],
                endWeights[projectIdx],
                endWeights[reserveIdx],
                startTime,
                endTime,
                blockProjectTokenSwapsIn
            );
    }

    function _createLBPoolWithMigration(
        address poolCreator,
        uint256 lockDurationAfterMigration,
        uint256 bptPercentageToMigrate,
        uint256 migrationWeightProjectToken,
        uint256 migrationWeightReserveToken
    ) internal virtual override returns (address newPool, bytes memory poolArgs) {
        LBPCommonParams memory lbpCommonParams = LBPCommonParams({
            name: "LBPool",
            symbol: "LBP",
            owner: bob,
            projectToken: projectToken,
            reserveToken: reserveToken,
            startTime: uint32(block.timestamp + DEFAULT_START_OFFSET),
            endTime: uint32(block.timestamp + DEFAULT_END_OFFSET),
            blockProjectTokenSwapsIn: DEFAULT_PROJECT_TOKENS_SWAP_IN
        });

        MigrationParams memory migrationParams = MigrationParams({
            lockDurationAfterMigration: lockDurationAfterMigration,
            bptPercentageToMigrate: bptPercentageToMigrate,
            migrationWeightProjectToken: migrationWeightProjectToken,
            migrationWeightReserveToken: migrationWeightReserveToken
        });

        LBPParams memory lbpParams = LBPParams({
            projectTokenStartWeight: startWeights[projectIdx],
            reserveTokenStartWeight: startWeights[reserveIdx],
            projectTokenEndWeight: endWeights[projectIdx],
            reserveTokenEndWeight: endWeights[reserveIdx]
        });

        // Copy to local variable to free up parameter stack slot.
        uint256 salt = _saltCounter++;
        address poolCreator_ = poolCreator;

        newPool = lbPoolFactory.createWithMigration(
            lbpCommonParams,
            migrationParams,
            lbpParams,
            swapFee,
            bytes32(salt),
            poolCreator_
        );

        poolArgs = abi.encode(
            lbpCommonParams,
            migrationParams,
            lbpParams,
            vault,
            address(router),
            address(migrationRouter),
            poolVersion
        );

        return (newPool, poolArgs);
    }

    function _createLBPoolWithCustomWeights(
        address poolCreator,
        uint256 projectTokenStartWeight,
        uint256 reserveTokenStartWeight,
        uint256 projectTokenEndWeight,
        uint256 reserveTokenEndWeight,
        uint32 startTime,
        uint32 endTime,
        bool blockProjectTokenSwapsIn
    ) internal returns (address newPool, bytes memory poolArgs) {
        LBPCommonParams memory lbpCommonParams = LBPCommonParams({
            name: "LBPool",
            symbol: "LBP",
            owner: bob,
            projectToken: projectToken,
            reserveToken: reserveToken,
            startTime: startTime,
            endTime: endTime,
            blockProjectTokenSwapsIn: blockProjectTokenSwapsIn
        });

        LBPParams memory lbpParams = LBPParams({
            projectTokenStartWeight: projectTokenStartWeight,
            reserveTokenStartWeight: reserveTokenStartWeight,
            projectTokenEndWeight: projectTokenEndWeight,
            reserveTokenEndWeight: reserveTokenEndWeight
        });

        MigrationParams memory migrationParams;

        FactoryParams memory factoryParams = FactoryParams({
            vault: vault,
            trustedRouter: address(router),
            migrationRouter: address(migrationRouter),
            poolVersion: poolVersion
        });

        // Copy to local variable to free up parameter stack slot.
        address poolCreator_ = poolCreator;
        uint256 salt = _saltCounter++;

        newPool = lbPoolFactory.create(lbpCommonParams, lbpParams, swapFee, bytes32(salt), poolCreator_);

        poolArgs = abi.encode(lbpCommonParams, migrationParams, lbpParams, vault, factoryParams);
    }
}
