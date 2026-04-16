// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { ILPOracleFactoryBase } from "@balancer-labs/v3-interfaces/contracts/oracles/ILPOracleFactoryBase.sol";
import { PoolRoleAccounts, TokenConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IWeightedLPOracle } from "@balancer-labs/v3-interfaces/contracts/oracles/IWeightedLPOracle.sol";
import { IWeightedPool } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/IWeightedPool.sol";
import { ILPOracleBase } from "@balancer-labs/v3-interfaces/contracts/oracles/ILPOracleBase.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { WeightedPoolFactory } from "@balancer-labs/v3-pool-weighted/contracts/WeightedPoolFactory.sol";
import { WeightedPoolMock } from "@balancer-labs/v3-pool-weighted/contracts/test/WeightedPoolMock.sol";
import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import {
    WeightedPoolContractsDeployer
} from "@balancer-labs/v3-pool-weighted/test/foundry/utils/WeightedPoolContractsDeployer.sol";
import { WeightedPool } from "@balancer-labs/v3-pool-weighted/contracts/WeightedPool.sol";

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
        // Solidity address-to-contract casts are zero-cost type annotations, and `getWeights()` is declared on the
        // `WeightedLPOracle` parent, so a mistakenly-deployed static oracle would also survive a cast + call. Prove
        // the oracle is dynamic by mutating the pool's live weights and verifying the oracle reflects the change.
        // A static `WeightedLPOracle` caches weights immutably at deployment and cannot pass this check.
        (WeightedPoolMock pool, AggregatorV3Interface[] memory feeds) = _createMockPoolAndFeeds();

        ILPOracleBase oracle = _factory.create(IBasePool(address(pool)), false, false, feeds);
        assertTrue(_factory.isOracleFromFactory(oracle), "Oracle not registered in factory");

        DynamicWeightedLPOracle dynamicOracle = DynamicWeightedLPOracle(address(oracle));
        uint256[] memory initialWeights = dynamicOracle.getWeights();
        assertEq(initialWeights.length, feeds.length, "Weights length should match number of feeds");

        uint256[2] memory newWeights;
        newWeights[0] = 25e16;
        newWeights[1] = 75e16;
        pool.setNormalizedWeights(newWeights);

        uint256[] memory updatedWeights = dynamicOracle.getWeights();
        assertEq(updatedWeights[0], newWeights[0], "Dynamic oracle did not reflect updated weight[0]");
        assertEq(updatedWeights[1], newWeights[1], "Dynamic oracle did not reflect updated weight[1]");
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

    function _createMockPoolAndFeeds() internal returns (WeightedPoolMock pool, AggregatorV3Interface[] memory feeds) {
        IERC20[] memory sortedTokens = InputHelpers.sortTokens(
            [address(dai), address(usdc)].toMemoryArray().asIERC20()
        );

        uint256[] memory weights = [uint256(50e16), 50e16].toMemoryArray();

        WeightedPool.NewPoolParams memory poolParams = WeightedPool.NewPoolParams({
            name: "Dynamic Weighted Pool Mock",
            symbol: "DYN-MOCK",
            numTokens: sortedTokens.length,
            normalizedWeights: weights,
            version: "",
            minTokenBalances: [uint256(1e12), uint256(1e12)].toMemoryArray()
        });
        pool = new WeightedPoolMock(poolParams, vault);

        vault.manualRegisterPoolWithSwapFee(address(pool), sortedTokens, 1e16);

        feeds = _createFeeds(IBasePool(address(pool)));
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
