// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IWeightedPool } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/IWeightedPool.sol";
import { ILPOracleBase } from "@balancer-labs/v3-interfaces/contracts/oracles/ILPOracleBase.sol";

import { WeightedPoolFactory } from "@balancer-labs/v3-pool-weighted/contracts/WeightedPoolFactory.sol";
import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import {
    WeightedPoolContractsDeployer
} from "@balancer-labs/v3-pool-weighted/test/foundry/utils/WeightedPoolContractsDeployer.sol";
import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { FeedMock } from "../../contracts/test/FeedMock.sol";
import { DynamicWeightedLPOracle } from "../../contracts/DynamicWeightedLPOracle.sol";

contract DynamicWeightedLPOracleTest is BaseVaultTest, WeightedPoolContractsDeployer {
    using FixedPoint for uint256;
    using CastingHelpers for address[];
    using ArrayHelpers for *;

    uint256 constant VERSION = 123;
    uint256 constant MAX_TOKENS = 8;
    uint256 constant MIN_TOKENS = 2;
    uint256 constant MIN_WEIGHT = 1e16; // 1%

    IERC20[] sortedTokens;

    WeightedPoolFactory weightedPoolFactory;
    uint256 poolCreationNonce;

    AggregatorV3Interface[] feeds;
    FeedMock sequencerUptimeFeed;
    uint256 uptimeResyncWindow = 1 hours;

    function setUp() public override {
        BaseVaultTest.setUp();

        (weightedPoolFactory, ) = WeightedPoolContractsDeployer.deploy(vault, 365 days);

        sequencerUptimeFeed = new FeedMock(0);
        // Default to indicating the feed has been up for a day.
        sequencerUptimeFeed.setLastRoundData(0, block.timestamp - 1 days);
    }

    function createAndInitPool(uint256 totalTokens) internal returns (IWeightedPool pool, uint256[] memory weights) {
        sortedTokens = new IERC20[](totalTokens);
        for (uint256 i = 0; i < totalTokens; i++) {
            sortedTokens[i] = tokens[i];
        }
        sortedTokens = InputHelpers.sortTokens(sortedTokens);

        weights = _createWeights(totalTokens);
        feeds = _createFeeds(totalTokens);

        pool = _createPool(sortedTokens.asIERC20(), weights);
        _initializePool(
            pool,
            sortedTokens,
            [uint256(1e3), 2e3, 3e3, 4e3, 5e3, 6e3, 7e3, 8e3].toMemoryArray().slice(0, totalTokens)
        );
    }

    function deployOracle(IWeightedPool pool) internal returns (DynamicWeightedLPOracle oracle) {
        oracle = new DynamicWeightedLPOracle(vault, pool, feeds, sequencerUptimeFeed, uptimeResyncWindow, VERSION);
    }

    function testGetWeights__Dynamic() public {
        uint256 totalTokens = 3;
        (IWeightedPool pool, uint256[] memory expectedWeights) = createAndInitPool(totalTokens);
        DynamicWeightedLPOracle oracle = deployOracle(pool);

        uint256[] memory oracleWeights = oracle.getWeights();

        for (uint256 i = 0; i < expectedWeights.length; i++) {
            assertEq(expectedWeights[i], oracleWeights[i], "Dynamic oracle weight does not match pool weight");
        }
    }

    function testGetWeights__Fuzz(uint256 totalTokens) public {
        totalTokens = bound(totalTokens, MIN_TOKENS, MAX_TOKENS);
        (IWeightedPool pool, uint256[] memory weights) = createAndInitPool(totalTokens);
        DynamicWeightedLPOracle oracle = deployOracle(pool);

        uint256[] memory returnedWeights = oracle.getWeights();
        for (uint256 i = 0; i < weights.length; i++) {
            assertEq(weights[i], returnedWeights[i], "Dynamic weight does not match expected weight");
        }
    }

    function _createWeights(uint256 totalTokens) private view returns (uint256[] memory weights) {
        weights = new uint256[](totalTokens);
        for (uint256 i = 0; i < totalTokens; i++) {
            weights[i] = MIN_WEIGHT + (i * 1e16);
        }

        uint256 sum = 0;
        for (uint256 i = 0; i < totalTokens; i++) {
            sum += weights[i];
        }

        // Normalize so they sum to 1
        for (uint256 i = 0; i < totalTokens; i++) {
            weights[i] = weights[i].divDown(sum);
        }

        // Ensure they sum to exactly 1e18
        uint256 actualSum = 0;
        for (uint256 i = 0; i < totalTokens - 1; i++) {
            actualSum += weights[i];
        }
        weights[totalTokens - 1] = FixedPoint.ONE - actualSum;
    }

    function _createFeeds(uint256 totalTokens) private returns (AggregatorV3Interface[] memory) {
        feeds = new AggregatorV3Interface[](totalTokens);
        for (uint256 i = 0; i < totalTokens; i++) {
            FeedMock feed = new FeedMock(18);
            feed.setLastRoundData(1e18, block.timestamp); // $1 price for each token
            feeds[i] = feed;
        }
        return feeds;
    }

    function _createPool(IERC20[] memory poolTokens, uint256[] memory poolWeights) private returns (IWeightedPool) {
        return
            IWeightedPool(
                weightedPoolFactory.create(
                    "50/50 Pool",
                    "50_50_POOL",
                    InputHelpers.sortTokens(poolTokens),
                    poolWeights,
                    poolCreationNonce++,
                    address(0)
                )
            );
    }

    function _initializePool(IWeightedPool pool, IERC20[] memory poolTokens, uint256[] memory initialBalances) private {
        vm.startPrank(lp);
        for (uint256 i = 0; i < poolTokens.length; i++) {
            poolTokens[i].approve(address(vault), type(uint256).max);
        }

        router.initialize(address(pool), poolTokens, initialBalances, 0, false, bytes(""));
        vm.stopPrank();
    }
}
