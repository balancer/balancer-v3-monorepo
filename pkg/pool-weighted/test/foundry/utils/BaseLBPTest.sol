// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { ContractType } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IBalancerContractRegistry.sol";
import { LBPParams } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPool.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { BalancerContractRegistry } from "@balancer-labs/v3-standalone-utils/contracts/BalancerContractRegistry.sol";
import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";

import { LBPoolFactory } from "../../../contracts/lbp/LBPoolFactory.sol";
import { WeightedPoolFactory } from "../../../contracts/WeightedPoolFactory.sol";
import { LBPMigrationRouterMock } from "../../../contracts/test/LBPMigrationRouterMock.sol";
import { LBPoolContractsDeployer } from "./LBPoolContractsDeployer.sol";
import { WeightedPoolContractsDeployer } from "./WeightedPoolContractsDeployer.sol";

contract BaseLBPTest is BaseVaultTest, LBPoolContractsDeployer, WeightedPoolContractsDeployer {
    using ArrayHelpers for *;
    using CastingHelpers for *;

    uint256 public constant swapFee = 1e16; // 1%

    string public constant factoryVersion = "Factory v1";
    string public constant poolVersion = "Pool v1";
    string public constant migrationRouterVersion = "Migration Router v1";

    uint256 internal constant TOKEN_COUNT = 2;
    uint256 internal constant HIGH_WEIGHT = uint256(70e16);
    uint256 internal constant LOW_WEIGHT = uint256(30e16);
    uint32 internal constant DEFAULT_START_OFFSET = 100;
    uint32 internal constant DEFAULT_END_OFFSET = 200;
    bool internal constant DEFAULT_PROJECT_TOKENS_SWAP_IN = true;

    IERC20 internal projectToken;
    IERC20 internal reserveToken;

    uint256[] internal startWeights;
    uint256[] internal endWeights;
    uint256 internal projectIdx;
    uint256 internal reserveIdx;

    uint256 private _saltCounter;

    WeightedPoolFactory internal weightedPoolFactory;
    BalancerContractRegistry internal balancerContractRegistry;
    LBPoolFactory internal lbPoolFactory;
    LBPMigrationRouterMock internal migrationRouter;

    function setUp() public virtual override {
        super.setUp();
    }

    function onAfterDeployMainContracts() internal override {
        projectToken = dai;
        reserveToken = usdc;

        (projectIdx, reserveIdx) = getSortedIndexes(address(projectToken), address(reserveToken));

        startWeights = new uint256[](2);
        startWeights[projectIdx] = HIGH_WEIGHT;
        startWeights[reserveIdx] = LOW_WEIGHT;

        endWeights = new uint256[](2);
        endWeights[projectIdx] = LOW_WEIGHT;
        endWeights[reserveIdx] = HIGH_WEIGHT;
    }

    function createPoolFactory() internal override returns (address) {
        weightedPoolFactory = deployWeightedPoolFactory(
            IVault(address(vault)),
            365 days,
            "Weighted Factory v1",
            "Weighted Pool v1"
        );

        balancerContractRegistry = new BalancerContractRegistry(IVault(address(vault)));
        authorizer.grantRole(
            balancerContractRegistry.getActionId(BalancerContractRegistry.registerBalancerContract.selector),
            admin
        );
        authorizer.grantRole(
            balancerContractRegistry.getActionId(BalancerContractRegistry.deprecateBalancerContract.selector),
            admin
        );

        vm.prank(admin);
        balancerContractRegistry.registerBalancerContract(
            ContractType.POOL_FACTORY,
            "WeightedPool",
            address(weightedPoolFactory)
        );

        migrationRouter = deployLBPMigrationRouterMock(balancerContractRegistry, migrationRouterVersion);
        vm.label(address(migrationRouter), "LBP migration router");

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

    function createPool() internal virtual override returns (address newPool, bytes memory poolArgs) {
        return
            _createLBPool(
                alice,
                uint32(block.timestamp + DEFAULT_START_OFFSET),
                uint32(block.timestamp + DEFAULT_END_OFFSET),
                DEFAULT_PROJECT_TOKENS_SWAP_IN
            );
    }

    function initPool() internal override {
        vm.startPrank(bob); // Bob is the owner of the pool.
        _initPool(pool, [poolInitAmount, poolInitAmount].toMemoryArray(), 0);
        vm.stopPrank();
    }

    function _createLBPool(
        address poolCreator,
        uint32 startTime,
        uint32 endTime,
        bool blockProjectTokenSwapsIn
    ) internal returns (address newPool, bytes memory poolArgs) {
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
        uint256 bptLockDuration,
        uint256 bptPercentageToMigrate,
        uint256 migrationWeightProjectToken,
        uint256 migrationWeightReserveToken
    ) internal returns (address newPool, bytes memory poolArgs) {
        string memory name = "LBPool";
        string memory symbol = "LBP";

        LBPParams memory lbpParams = LBPParams({
            owner: bob,
            projectToken: projectToken,
            reserveToken: reserveToken,
            projectTokenStartWeight: startWeights[projectIdx],
            reserveTokenStartWeight: startWeights[reserveIdx],
            projectTokenEndWeight: endWeights[projectIdx],
            reserveTokenEndWeight: endWeights[reserveIdx],
            startTime: uint32(block.timestamp + DEFAULT_START_OFFSET),
            endTime: uint32(block.timestamp + DEFAULT_END_OFFSET),
            blockProjectTokenSwapsIn: DEFAULT_PROJECT_TOKENS_SWAP_IN
        });

        // stack-too-deep
        uint256 salt = _saltCounter++;
        address poolCreator_ = poolCreator;
        uint256 bptLockDuration_ = bptLockDuration;
        uint256 bptPercentageToMigrate_ = bptPercentageToMigrate;
        uint256 migrationWeightProjectToken_ = migrationWeightProjectToken;
        uint256 migrationWeightReserveToken_ = migrationWeightReserveToken;

        newPool = lbPoolFactory.createWithMigration(
            name,
            symbol,
            lbpParams,
            swapFee,
            bytes32(salt),
            poolCreator_,
            bptLockDuration_,
            bptPercentageToMigrate_,
            migrationWeightProjectToken_,
            migrationWeightReserveToken_
        );

        poolArgs = abi.encode(name, symbol, lbpParams, vault, address(router), address(migrationRouter), poolVersion);

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
        string memory name = "LBPool";
        string memory symbol = "LBP";

        LBPParams memory lbpParams = LBPParams({
            owner: bob,
            projectToken: projectToken,
            reserveToken: reserveToken,
            projectTokenStartWeight: projectTokenStartWeight,
            reserveTokenStartWeight: reserveTokenStartWeight,
            projectTokenEndWeight: projectTokenEndWeight,
            reserveTokenEndWeight: reserveTokenEndWeight,
            startTime: startTime,
            endTime: endTime,
            blockProjectTokenSwapsIn: blockProjectTokenSwapsIn
        });

        // stack-too-deep
        uint256 salt = _saltCounter++;
        address poolCreator_ = poolCreator;

        newPool = lbPoolFactory.create(name, symbol, lbpParams, swapFee, bytes32(salt), poolCreator_);

        poolArgs = abi.encode(name, symbol, lbpParams, vault, address(router), address(migrationRouter), poolVersion);
    }
}
