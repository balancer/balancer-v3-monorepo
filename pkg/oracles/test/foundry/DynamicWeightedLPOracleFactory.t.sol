// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

import { ILPOracleFactoryBase } from "@balancer-labs/v3-interfaces/contracts/oracles/ILPOracleFactoryBase.sol";
import { PoolRoleAccounts, TokenConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IWeightedLPOracle } from "@balancer-labs/v3-interfaces/contracts/oracles/IWeightedLPOracle.sol";
import { IWeightedPool } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/IWeightedPool.sol";
import { ILPOracleBase } from "@balancer-labs/v3-interfaces/contracts/oracles/ILPOracleBase.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { WeightedPoolFactory } from "@balancer-labs/v3-pool-weighted/contracts/WeightedPoolFactory.sol";
import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import {
    WeightedPoolContractsDeployer
} from "@balancer-labs/v3-pool-weighted/test/foundry/utils/WeightedPoolContractsDeployer.sol";

import { DynamicWeightedLPOracleFactory } from "../../contracts/DynamicWeightedLPOracleFactory.sol";
import { DynamicWeightedLPOracle } from "../../contracts/DynamicWeightedLPOracle.sol";
import { LPOracleFactoryBaseTest } from "./LPOracleFactoryBase.t.sol";

contract DynamicWeightedLPOracleFactoryTest is WeightedPoolContractsDeployer, LPOracleFactoryBaseTest {
    using ArrayHelpers for *;
    using CastingHelpers for address[];

    WeightedPoolFactory _weightedPoolFactory;

    function setUp() public virtual override {
        super.setUp();

        _weightedPoolFactory = deployWeightedPoolFactory(IVault(address(vault)), 365 days, "Factory v1", "Pool v1");
    }

    function testCreateEmitsEvent() external {
        IBasePool pool = _createAndInitPool();
        AggregatorV3Interface[] memory feeds = _createFeeds(pool);

        bool shouldUseBlockTimeForOldestFeedUpdate = true;
        bool shouldRevertIfVaultUnlocked = true;

        // Snapshot is needed to predict what will be the oracle address.
        uint256 snapshot = vm.snapshotState();
        ILPOracleBase oracle = _factory.create(
            pool,
            shouldUseBlockTimeForOldestFeedUpdate,
            shouldRevertIfVaultUnlocked,
            feeds
        );
        vm.revertToState(snapshot);

        vm.expectEmit();
        emit DynamicWeightedLPOracleFactory.DynamicWeightedLPOracleCreated(
            IWeightedPool(address(pool)),
            shouldUseBlockTimeForOldestFeedUpdate,
            shouldRevertIfVaultUnlocked,
            feeds,
            IWeightedLPOracle(address(oracle))
        );
        _factory.create(pool, shouldUseBlockTimeForOldestFeedUpdate, shouldRevertIfVaultUnlocked, feeds);
    }

    function testCreateDeploysDynamicOracle() external {
        IBasePool pool = _createAndInitPool();
        AggregatorV3Interface[] memory feeds = _createFeeds(pool);

        ILPOracleBase oracle = _factory.create(pool, false, false, feeds);

        // Verify the deployed contract is a DynamicWeightedLPOracle (not the static WeightedLPOracle).
        // If the cast is wrong this line will revert since getWeights() is the same on both; we instead
        // check that the oracle is tracked by the factory and that a type-cast to DynamicWeightedLPOracle
        // does not revert when calling its overridden getWeights().
        assertTrue(_factory.isOracleFromFactory(oracle), "Oracle not registered in factory");
        // This will revert with a bad cast if the factory deployed a WeightedLPOracle instead.
        uint256[] memory weights = DynamicWeightedLPOracle(address(oracle)).getWeights();
        assertEq(weights.length, feeds.length, "Weights length should match number of feeds");
    }

    function _createAndInitPool() internal override returns (IBasePool) {
        return
            _createAndInitPool(
                [poolInitAmount, poolInitAmount].toMemoryArray(),
                [50e16, uint256(50e16)].toMemoryArray(),
                vault.buildTokenConfig([address(dai), address(usdc)].toMemoryArray().asIERC20())
            );
    }

    function _createAndInitPool(
        uint256[] memory initAmounts,
        uint256[] memory weights,
        TokenConfig[] memory tokenConfigs
    ) internal returns (IBasePool) {
        string memory name = "Dynamic Weighted Pool Test";
        string memory symbol = "DYN-WEIGHTED-TEST";

        PoolRoleAccounts memory roleAccounts;

        address newPool = _weightedPoolFactory.create(
            name,
            symbol,
            tokenConfigs,
            weights,
            roleAccounts,
            DEFAULT_SWAP_FEE_PERCENTAGE,
            address(0),
            true,
            false,
            bytes32("")
        );

        vm.startPrank(lp);
        _initPool(newPool, initAmounts, 0);
        vm.stopPrank();

        _setSwapFeePercentage(newPool, 0);

        return IBasePool(newPool);
    }

    function _createOracleFactory() internal override returns (ILPOracleFactoryBase) {
        return
            ILPOracleFactoryBase(
                address(
                    new DynamicWeightedLPOracleFactory(
                        vault,
                        _uptimeFeed,
                        UPTIME_RESYNC_WINDOW,
                        ORACLE_FACTORY_VERSION,
                        ORACLE_VERSION
                    )
                )
            );
    }
}
