// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { ISequencerUptimeFeed } from "@balancer-labs/v3-interfaces/contracts/oracles/ISequencerUptimeFeed.sol";
import { ILPOracleBase } from "@balancer-labs/v3-interfaces/contracts/oracles/ILPOracleBase.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";

import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";

import { LPOracleBase } from "../../../contracts/LPOracleBase.sol";
import { FeedMock } from "../../../contracts/test/FeedMock.sol";

// This is a function shared between multiple mocks; adding the interface allows more tests to be factored out.
interface ILPOracleBaseMock {
    function computeFeedTokenDecimalScalingFactor(AggregatorV3Interface feed) external view returns (uint256);
}

// Common test contract for LP Oracles, encompassing the sequencer uptime feed and related tests.
abstract contract BaseLPOracleTest is BaseVaultTest {
    uint256 constant MIN_TOKENS = 2;
    uint256 constant VAULT_MAX_TOKENS = 8;
    uint256 constant VERSION = 123;

    // Uptime sequencer code.
    uint256 constant SEQUENCER_STATUS_DOWN = 1;

    uint256 constant UPTIME_RESYNC_WINDOW = 1 hours;

    LPOracleBase internal oracle;
    AggregatorV3Interface[] internal feeds;

    FeedMock uptimeFeed;

    IERC20[] sortedTokens;

    bool shouldUseBlockTimeForOldestFeedUpdate;
    bool shouldRevertIfVaultUnlocked;

    function setUp() public virtual override {
        for (uint256 i = 0; i < getMaxTokens(); i++) {
            tokens.push(createERC20(string(abi.encodePacked("TK", i)), 18 - uint8(i % 6)));
        }

        sortedTokens = InputHelpers.sortTokens(tokens);

        super.setUp();

        uptimeFeed = new FeedMock(18);
        // Default to indicating the feed has been up for a day.
        uptimeFeed.setLastRoundData(0, block.timestamp - 1 days);
    }

    function getMaxTokens() public view virtual returns (uint256);

    // Deploy and initialize pool, then create the oracle and set the `oracle` and `feeds` variables.
    function createOracle(uint256 numTokens) public virtual returns (IBasePool);

    function createOracle() internal returns (IBasePool) {
        return createOracle(2);
    }

    function setShouldUseBlockTimeForOldestFeedUpdate(bool shouldUseBlockTimeForOldestFeedUpdate_) public {
        shouldUseBlockTimeForOldestFeedUpdate = shouldUseBlockTimeForOldestFeedUpdate_;
    }

    function setShouldRevertIfVaultUnlocked(bool shouldRevertIfVaultUnlocked_) public {
        shouldRevertIfVaultUnlocked = shouldRevertIfVaultUnlocked_;
    }

    function testDecimals() public {
        createOracle();

        assertEq(oracle.decimals(), 18, "Decimals does not match");
    }

    function testVersion() public {
        createOracle();

        assertEq(oracle.version(), VERSION, "Version does not match");
    }

    /**
     * forge-config: default.fuzz.runs = 10
     * forge-config: intense.fuzz.runs = 50
     */
    function testGetFeeds__Fuzz(uint256 totalTokens) public {
        totalTokens = bound(totalTokens, MIN_TOKENS, getMaxTokens());
        createOracle();

        AggregatorV3Interface[] memory returnedFeeds = oracle.getFeeds();

        assertEq(feeds.length, returnedFeeds.length, "Feeds length does not match");

        for (uint256 i = 0; i < feeds.length; i++) {
            assertEq(address(feeds[i]), address(returnedFeeds[i]), "Feed does not match");
        }
    }

    /**
     * forge-config: default.fuzz.runs = 10
     * forge-config: intense.fuzz.runs = 50
     */
    function testGetFeedTokenDecimalScalingFactors__Fuzz(uint256 totalTokens) public {
        totalTokens = bound(totalTokens, MIN_TOKENS, getMaxTokens());
        createOracle(totalTokens);

        uint256[] memory returnedScalingFactors = oracle.getFeedTokenDecimalScalingFactors();

        for (uint256 i = 0; i < feeds.length; i++) {
            assertEq(
                ILPOracleBaseMock(address(oracle)).computeFeedTokenDecimalScalingFactor(feeds[i]),
                returnedScalingFactors[i],
                "Scaling factor does not match"
            );
        }
    }

    /**
     * forge-config: default.fuzz.runs = 10
     * forge-config: intense.fuzz.runs = 50
     */
    function testCalculateFeedTokenDecimalScalingFactor__Fuzz(uint256 totalTokens) public {
        totalTokens = bound(totalTokens, MIN_TOKENS, getMaxTokens());
        createOracle(totalTokens);

        for (uint256 i = 0; i < feeds.length; i++) {
            assertEq(
                ILPOracleBaseMock(address(oracle)).computeFeedTokenDecimalScalingFactor(feeds[i]),
                10 ** (18 - IERC20Metadata(address(feeds[i])).decimals()),
                "Scaling factor does not match"
            );
        }
    }

    function testGetFeedData__Fuzz(
        uint256 totalTokens,
        uint256[VAULT_MAX_TOKENS] memory answersRaw,
        uint256[VAULT_MAX_TOKENS] memory updateTimestampsRaw
    ) public {
        totalTokens = bound(totalTokens, MIN_TOKENS, getMaxTokens());

        createOracle(totalTokens);

        uint256[] memory answers = new uint256[](totalTokens);
        uint256[] memory updateTimestamps = new uint256[](totalTokens);
        for (uint256 i = 0; i < totalTokens; i++) {
            answers[i] = bound(answersRaw[i], 1, MAX_UINT128);
            updateTimestamps[i] = block.timestamp - bound(updateTimestampsRaw[i], 1, 100);
        }

        for (uint256 i = 0; i < totalTokens; i++) {
            FeedMock(address(feeds[i])).setLastRoundData(answers[i], updateTimestamps[i]);
        }

        (int256[] memory returnedAnswers, uint256[] memory returnedTimestamps) = oracle.getFeedData();
        for (uint256 i = 0; i < totalTokens; i++) {
            assertEq(
                uint256(returnedAnswers[i]),
                answers[i] * oracle.getFeedTokenDecimalScalingFactors()[i],
                "Answer does not match"
            );

            assertEq(returnedTimestamps[i], updateTimestamps[i], "Timestamp does not match");
        }
    }

    function testComputeTVL__Fuzz(
        uint256 totalTokens,
        uint256[8] memory answersRaw,
        uint256[8] memory updateTimestampsRaw
    ) public {
        totalTokens = bound(totalTokens, MIN_TOKENS, getMaxTokens());

        uint256[] memory answers = new uint256[](totalTokens);
        uint256[] memory updateTimestamps = new uint256[](totalTokens);
        for (uint256 i = 0; i < totalTokens; i++) {
            answers[i] = bound(answersRaw[i], 5e17, 5e18); // 0.5 to 5 for stable assets
            updateTimestamps[i] = block.timestamp - bound(updateTimestampsRaw[i], 1, 100);
        }

        // Create a pool with 18-decimal tokens, so that we don't overflow.
        createOracle(totalTokens);

        for (uint256 i = 0; i < totalTokens; i++) {
            FeedMock(address(feeds[i])).setLastRoundData(answers[i], updateTimestamps[i]);
        }

        (int256[] memory returnedAnswers, uint256[] memory returnedTimestamps) = oracle.getFeedData();
        for (uint256 i = 0; i < totalTokens; i++) {
            assertEq(
                uint256(returnedAnswers[i]),
                answers[i] * oracle.getFeedTokenDecimalScalingFactors()[i],
                "Answer does not match"
            );

            assertEq(returnedTimestamps[i], updateTimestamps[i], "Timestamp does not match");
        }

        uint256 tvlWithPrices = oracle.computeTVLGivenPrices(returnedAnswers);
        uint256 tvl = oracle.computeTVL();

        assertEq(tvl, tvlWithPrices, "Alternate TVL computations don't match");
    }

    function testUnsupportedDecimals() public {
        createOracle();

        AggregatorV3Interface feedWith20Decimals = AggregatorV3Interface(address(new FeedMock(20)));

        vm.expectRevert(ILPOracleBase.UnsupportedDecimals.selector);
        ILPOracleBaseMock(address(oracle)).computeFeedTokenDecimalScalingFactor(feedWith20Decimals);
    }

    function testLengthMismatchTVL() public {
        createOracle();

        int256[] memory prices = new int256[](3);

        vm.expectRevert(InputHelpers.InputLengthMismatch.selector);
        oracle.computeTVLGivenPrices(prices);
    }

    function testZeroPrice() public virtual {
        createOracle();

        int256[] memory prices = new int256[](2);

        vm.expectRevert(ILPOracleBase.InvalidOraclePrice.selector);
        oracle.computeTVLGivenPrices(prices);
    }

    function testNegativePrice() public virtual {
        createOracle();

        int256[] memory prices = new int256[](2);
        prices[0] = 1e18;
        prices[1] = -1e6;

        vm.expectRevert(ILPOracleBase.InvalidOraclePrice.selector);
        oracle.computeTVLGivenPrices(prices);
    }

    /**
     * forge-config: default.fuzz.runs = 10
     * forge-config: intense.fuzz.runs = 50
     */
    function testGetPoolTokens(uint256 totalTokens) public {
        totalTokens = bound(totalTokens, MIN_TOKENS, getMaxTokens());
        IBasePool pool = createOracle(totalTokens);

        IERC20[] memory returnedTokens = oracle.getPoolTokens();
        IERC20[] memory registeredTokens = vault.getPoolTokens(address(pool));

        assertEq(returnedTokens.length, registeredTokens.length, "Tokens length does not match");
        for (uint256 i = 0; i < returnedTokens.length; i++) {
            assertEq(address(returnedTokens[i]), address(registeredTokens[i]), "Tokens do not match");
        }
    }

    function testGetUptimeFeed() public {
        createOracle();

        assertEq(address(oracle.getSequencerUptimeFeed()), address(uptimeFeed), "Wrong uptime feed");
    }

    function testGetUptimeResyncWindow() public {
        createOracle();

        assertEq(oracle.getUptimeResyncWindow(), UPTIME_RESYNC_WINDOW, "Wrong uptime resync window");
    }

    function testUptimeSequencerDown() public {
        createOracle();

        uptimeFeed.setLastRoundData(SEQUENCER_STATUS_DOWN, 0);

        vm.expectRevert(ISequencerUptimeFeed.SequencerDown.selector);
        oracle.latestRoundData();
    }

    function testUptimeResyncIncomplete() public {
        createOracle();
        uptimeFeed.setStartedAt(block.timestamp - 100);

        vm.expectRevert(ISequencerUptimeFeed.SequencerResyncIncomplete.selector);
        oracle.latestRoundData();
    }

    function testUpdatedAtFlagGetter() public {
        createOracle();

        assertFalse(oracle.getShouldUseBlockTimeForOldestFeedUpdate(), "Flag should be false");

        setShouldUseBlockTimeForOldestFeedUpdate(true);
        createOracle();

        assertTrue(oracle.getShouldUseBlockTimeForOldestFeedUpdate(), "Flag should be true");
    }

    function testVaultUnlockedFlagGetter() public {
        createOracle();

        assertFalse(oracle.getShouldRevertIfVaultUnlocked(), "Flag should be false");

        setShouldRevertIfVaultUnlocked(true);
        createOracle();

        assertTrue(oracle.getShouldRevertIfVaultUnlocked(), "Flag should be true");
    }

    function testComputeTVLWithVaultUnlocked() public {
        setShouldRevertIfVaultUnlocked(true);

        oracle = _createValidOracle();

        vault.forceUnlock();

        // Non TVL-related things should work.
        assertEq(oracle.decimals(), 18, "Wrong decimals");

        vm.expectRevert(ILPOracleBase.VaultIsUnlocked.selector);
        oracle.latestRoundData();

        vm.expectRevert(ILPOracleBase.VaultIsUnlocked.selector);
        oracle.computeTVL();

        int256[] memory prices = new int256[](2);
        prices[0] = 1e18;
        prices[1] = 1e18;

        vm.expectRevert(ILPOracleBase.VaultIsUnlocked.selector);
        oracle.computeTVLGivenPrices(prices);
    }

    // Used in base tests
    function _createValidOracle() internal virtual returns (LPOracleBase);
}
