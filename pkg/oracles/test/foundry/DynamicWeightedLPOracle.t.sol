// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IWeightedPool } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/IWeightedPool.sol";
import { WeightedPoolMock } from "@balancer-labs/v3-pool-weighted/contracts/test/WeightedPoolMock.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { WeightedPool } from "@balancer-labs/v3-pool-weighted/contracts/WeightedPool.sol";

import { DynamicWeightedLPOracleMock } from "../../contracts/test/DynamicWeightedLPOracleMock.sol";
import { DynamicWeightedLPOracle } from "../../contracts/DynamicWeightedLPOracle.sol";
import { LPOracleBase } from "../../contracts/LPOracleBase.sol";
import { WeightedLPOracleTest } from "./WeightedLPOracle.t.sol";
import { FeedMock } from "../../contracts/test/FeedMock.sol";

contract DynamicWeightedLPOracleTest is WeightedLPOracleTest {
    uint256 constant NUM_TOKENS = 2;

    FeedMock sequencerUptimeFeed;
    uint256 uptimeResyncWindow = 1 hours;

    function setUp() public override {
        super.setUp();

        sequencerUptimeFeed = new FeedMock(0);
        // Default to indicating the feed has been up for a day.
        sequencerUptimeFeed.setLastRoundData(0, block.timestamp - 1 days);
    }

    function _createAndInitPool() private returns (WeightedPoolMock pool, uint256[] memory weights) {
        IERC20[] memory sortedTokens = new IERC20[](NUM_TOKENS);
        for (uint256 i = 0; i < NUM_TOKENS; i++) {
            sortedTokens[i] = tokens[i];
        }
        sortedTokens = InputHelpers.sortTokens(sortedTokens);

        // Start with 80/20
        weights = _createWeights(20e16);

        pool = _createPool(sortedTokens, weights);
    }

    function deployOracle(
        IWeightedPool pool
    ) internal override returns (LPOracleBase oracle, AggregatorV3Interface[] memory feeds) {
        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(address(pool));

        feeds = new AggregatorV3Interface[](tokens.length);

        for (uint256 i = 0; i < tokens.length; i++) {
            feeds[i] = AggregatorV3Interface(address(new FeedMock(IERC20Metadata(address(tokens[i])).decimals())));
        }

        oracle = new DynamicWeightedLPOracleMock(
            vault,
            pool,
            feeds,
            uptimeFeed,
            UPTIME_RESYNC_WINDOW,
            shouldUseBlockTimeForOldestFeedUpdate,
            VERSION
        );
    }

    function supportsBlockTimeFeedUpdate() internal pure override returns (bool) {
        return false;
    }

    // From BaseLPOracleTest
    function getMaxTokens() public pure override returns (uint256) {
        return NUM_TOKENS;
    }

    function testGetDynamicWeights() public {
        (WeightedPoolMock pool, uint256[] memory expectedWeights) = _createAndInitPool();
        (LPOracleBase _oracle, ) = deployOracle(pool);
        DynamicWeightedLPOracle oracle = DynamicWeightedLPOracle(address(_oracle));

        uint256[] memory oracleWeights = oracle.getWeights();

        assertEq(oracleWeights[0], expectedWeights[0], "Dynamic oracle weight does not match pool weight[0]");
        assertEq(oracleWeights[1], expectedWeights[1], "Dynamic oracle weight does not match pool weight[1]");

        uint256[2] memory newWeights;
        newWeights[0] = 75e16;
        newWeights[1] = 25e16;
        pool.setNormalizedWeights(newWeights);

        oracleWeights = oracle.getWeights();
        assertEq(oracleWeights[0], newWeights[0], "Dynamic oracle weight does not match (new) pool weight[0]");
        assertEq(oracleWeights[1], newWeights[1], "Dynamic oracle weight does not match (new) pool weight[1]");
    }

    function testGetDynamicWeights__Fuzz(uint256 weight0) public {
        weight0 = bound(weight0, MIN_WEIGHT, FixedPoint.ONE - MIN_WEIGHT);
        (WeightedPoolMock pool, uint256[] memory weights) = _createAndInitPool();
        (LPOracleBase _oracle, ) = deployOracle(pool);
        DynamicWeightedLPOracle oracle = DynamicWeightedLPOracle(address(_oracle));

        uint256[] memory oracleWeights = oracle.getWeights();
        for (uint256 i = 0; i < weights.length; i++) {
            assertEq(weights[i], oracleWeights[i], "Dynamic weight does not match expected weight");
        }

        uint256[2] memory newWeights;
        newWeights[0] = weight0;
        newWeights[1] = FixedPoint.ONE - weight0;
        pool.setNormalizedWeights(newWeights);

        oracleWeights = oracle.getWeights();
        assertEq(oracleWeights[0], newWeights[0], "Dynamic oracle weight does not match (new) pool weight[0]");
        assertEq(oracleWeights[1], newWeights[1], "Dynamic oracle weight does not match (new) pool weight[1]");
    }

    function _createWeights(uint256 weight0) private pure returns (uint256[] memory weights) {
        weights = new uint256[](NUM_TOKENS);
        weights[0] = weight0;
        weights[1] = FixedPoint.ONE - weight0;
    }

    function _createFeeds() private returns (AggregatorV3Interface[] memory feeds) {
        feeds = new AggregatorV3Interface[](NUM_TOKENS);
        for (uint256 i = 0; i < NUM_TOKENS; i++) {
            FeedMock feed = new FeedMock(18);
            feed.setLastRoundData(1e18, block.timestamp); // $1 price for each token
            feeds[i] = feed;
        }
        return feeds;
    }

    function _createPool(IERC20[] memory tokens, uint256[] memory poolWeights) private returns (WeightedPoolMock pool) {
        WeightedPool.NewPoolParams memory poolParams = WeightedPool.NewPoolParams({
            name: "Test",
            symbol: "TST",
            numTokens: NUM_TOKENS,
            normalizedWeights: poolWeights,
            version: ""
        });
        pool = new WeightedPoolMock(poolParams, vault);

        vault.manualRegisterPoolWithSwapFee(address(pool), tokens, 1e16);
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
