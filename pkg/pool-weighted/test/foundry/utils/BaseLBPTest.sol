// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { ContractType } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IBalancerContractRegistry.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { BalancerContractRegistry } from "@balancer-labs/v3-standalone-utils/contracts/BalancerContractRegistry.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";

import { LBPMigrationRouterMock } from "../../../contracts/test/LBPMigrationRouterMock.sol";
import { WeightedPoolContractsDeployer } from "./WeightedPoolContractsDeployer.sol";
import { LBPMigrationRouterDeployer } from "./LBPMigrationRouterDeployer.sol";
import { WeightedPoolFactory } from "../../../contracts/WeightedPoolFactory.sol";

abstract contract BaseLBPTest is BaseVaultTest, WeightedPoolContractsDeployer, LBPMigrationRouterDeployer {
    using ArrayHelpers for *;

    uint256 public constant swapFee = 1e16; // 1%

    string public constant factoryVersion = "Factory v1";
    string public constant poolVersion = "Pool v1";
    string public constant migrationRouterVersion = "Migration Router v1";

    uint256 internal constant TOKEN_COUNT = 2;
    uint32 internal constant DEFAULT_START_OFFSET = 100;
    uint32 internal constant DEFAULT_END_OFFSET = 200;
    bool internal constant DEFAULT_PROJECT_TOKENS_SWAP_IN = true;

    IERC20 internal projectToken;
    IERC20 internal reserveToken;

    uint256 internal projectIdx;
    uint256 internal reserveIdx;

    uint256 internal _saltCounter;

    BalancerContractRegistry internal balancerContractRegistry;
    WeightedPoolFactory internal weightedPoolFactory;
    LBPMigrationRouterMock internal migrationRouter;

    function setUp() public virtual override {
        super.setUp();
    }

    function onAfterDeployMainContracts() internal virtual override {
        projectToken = dai;
        reserveToken = usdc;

        (projectIdx, reserveIdx) = getSortedIndexes(address(projectToken), address(reserveToken));

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
    }

    function initPool() internal virtual override {
        vm.startPrank(bob); // Bob is the owner of the pool.
        _initPool(pool, [poolInitAmount, poolInitAmount].toMemoryArray(), 0);
        vm.stopPrank();
    }

    function _createLBPool(
        address poolCreator,
        uint32 startTime,
        uint32 endTime,
        bool blockProjectTokenSwapsIn
    ) internal virtual returns (address newPool, bytes memory poolArgs) {
        // solhint-disable-previous-line no-empty-blocks
    }

    function _createLBPoolWithMigration(
        address poolCreator,
        uint256 lockDurationAfterMigration,
        uint256 bptPercentageToMigrate,
        uint256 migrationWeightProjectToken,
        uint256 migrationWeightReserveToken
    ) internal virtual returns (address newPool, bytes memory poolArgs) {
        // solhint-disable-previous-line no-empty-blocks
    }
}
