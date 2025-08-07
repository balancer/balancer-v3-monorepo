// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {
    PoolRoleAccounts,
    Rounding,
    TokenConfig,
    TokenType
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IGyroECLPPool } from "@balancer-labs/v3-interfaces/contracts/pool-gyro/IGyroECLPPool.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { ILPOracleBase } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/ILPOracleBase.sol";
import { RateProviderMock } from "@balancer-labs/v3-vault/contracts/test/RateProviderMock.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { GyroEclpPoolDeployer } from "@balancer-labs/v3-pool-gyro/test/foundry/utils/GyroEclpPoolDeployer.sol";

import { FeedMock } from "../../contracts/test/FeedMock.sol";
import { EclpLPOracleMock } from "../../contracts/test/EclpLPOracleMock.sol";

contract EclpLPOracleTest is BaseVaultTest, GyroEclpPoolDeployer {
    using FixedPoint for uint256;
    using CastingHelpers for address[];
    using ArrayHelpers for *;

    uint256 constant VERSION = 123;
    uint256 constant NUM_TOKENS = 2;

    event Log(address indexed value);
    event LogUint(uint256 indexed value);

    IERC20[] sortedTokens;

    uint256 poolCreationNonce;

    function setUp() public virtual override {
        for (uint256 i = 0; i < NUM_TOKENS; i++) {
            tokens.push(createERC20(string(abi.encodePacked("TK", i)), 18 - uint8(i % 6)));
        }

        sortedTokens = InputHelpers.sortTokens(tokens);

        super.setUp();
    }

    function deployOracle(
        IGyroECLPPool pool
    ) internal returns (EclpLPOracleMock oracle, AggregatorV3Interface[] memory feeds) {
        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(address(pool));

        feeds = new AggregatorV3Interface[](tokens.length);

        for (uint256 i = 0; i < tokens.length; i++) {
            feeds[i] = AggregatorV3Interface(address(new FeedMock(IERC20Metadata(address(tokens[i])).decimals())));
        }

        oracle = new EclpLPOracleMock(IVault(address(vault)), pool, feeds, VERSION);
    }

    function createAndInitPool() internal returns (IGyroECLPPool) {
        address[] memory _tokens = new address[](NUM_TOKENS);
        uint256[] memory poolInitAmounts = new uint256[](NUM_TOKENS);

        for (uint256 i = 0; i < NUM_TOKENS; i++) {
            _tokens[i] = address(sortedTokens[i]);
            poolInitAmounts[i] = poolInitAmount;
        }

        return createAndInitPool(_tokens, poolInitAmounts);
    }

    function createAndInitPool(
        address[] memory _tokens,
        uint256[] memory initAmounts
    ) internal returns (IGyroECLPPool) {
        return createAndInitPool(_tokens, new IRateProvider[](tokens.length), initAmounts);
    }

    function createAndInitPool(
        address[] memory _tokens,
        IRateProvider[] memory rateProviders,
        uint256[] memory initAmounts
    ) internal returns (IGyroECLPPool) {
        string memory name = "ECLP-Test";

        PoolRoleAccounts memory roleAccounts;

        (address newPool, ) = createGyroEclpPool(_tokens, rateProviders, name, vault, lp);

        vm.startPrank(lp);
        _initPool(newPool, initAmounts, 0);
        vm.stopPrank();

        _setSwapFeePercentage(newPool, 0);

        return IGyroECLPPool(newPool);
    }

    function testDecimals() public {
        IGyroECLPPool pool = createAndInitPool();
        (EclpLPOracleMock oracle, ) = deployOracle(pool);

        assertEq(oracle.decimals(), 18, "Decimals does not match");
    }

    function testVersion() public {
        IGyroECLPPool pool = createAndInitPool();
        (EclpLPOracleMock oracle, ) = deployOracle(pool);

        assertEq(oracle.version(), VERSION, "Version does not match");
    }

    function testDescription() public {
        IGyroECLPPool pool = createAndInitPool();
        (EclpLPOracleMock oracle, ) = deployOracle(pool);

        assertEq(oracle.description(), "ECLP-Test/USD", "Description does not match");
    }

    function testGetFeeds() public {
        IGyroECLPPool pool = createAndInitPool();

        (EclpLPOracleMock oracle, AggregatorV3Interface[] memory feeds) = deployOracle(pool);

        AggregatorV3Interface[] memory returnedFeeds = oracle.getFeeds();

        assertEq(feeds.length, returnedFeeds.length, "Feeds length does not match");

        for (uint256 i = 0; i < feeds.length; i++) {
            assertEq(address(feeds[i]), address(returnedFeeds[i]), "Feed does not match");
        }
    }

    function testGetFeedTokenDecimalScalingFactors() public {
        IGyroECLPPool pool = createAndInitPool();

        (EclpLPOracleMock oracle, AggregatorV3Interface[] memory feeds) = deployOracle(pool);

        uint256[] memory returnedScalingFactors = oracle.getFeedTokenDecimalScalingFactors();

        for (uint256 i = 0; i < feeds.length; i++) {
            assertEq(
                oracle.computeFeedTokenDecimalScalingFactor(feeds[i]),
                returnedScalingFactors[i],
                "Scaling factor does not match"
            );
        }
    }

    function testUnsupportedDecimals() public {
        IGyroECLPPool pool = createAndInitPool();
        (EclpLPOracleMock oracle, ) = deployOracle(pool);

        AggregatorV3Interface feedWith20Decimals = AggregatorV3Interface(address(new FeedMock(20)));

        vm.expectRevert(ILPOracleBase.UnsupportedDecimals.selector);
        oracle.computeFeedTokenDecimalScalingFactor(feedWith20Decimals);
    }

    function testCalculateFeedTokenDecimalScalingFactor() public {
        IGyroECLPPool pool = createAndInitPool();
        (EclpLPOracleMock oracle, AggregatorV3Interface[] memory feeds) = deployOracle(pool);

        for (uint256 i = 0; i < feeds.length; i++) {
            assertEq(
                oracle.computeFeedTokenDecimalScalingFactor(feeds[i]),
                10 ** (18 - IERC20Metadata(address(feeds[i])).decimals()),
                "Scaling factor does not match"
            );
        }
    }

    function testGetPoolTokens() public {
        IGyroECLPPool pool = createAndInitPool();
        (EclpLPOracleMock oracle, ) = deployOracle(pool);

        IERC20[] memory returnedTokens = oracle.getPoolTokens();
        IERC20[] memory registeredTokens = vault.getPoolTokens(address(pool));

        assertEq(returnedTokens.length, registeredTokens.length, "Tokens length does not match");
        for (uint256 i = 0; i < returnedTokens.length; i++) {
            assertEq(address(returnedTokens[i]), address(registeredTokens[i]), "Tokens does not match");
        }
    }

    function testGetFeedData__Fuzz(
        uint256[NUM_TOKENS] memory answersRaw,
        uint256[NUM_TOKENS] memory updateTimestampsRaw
    ) public {
        uint256 minUpdateTimestamp = MAX_UINT256;
        uint256[] memory answers = new uint256[](NUM_TOKENS);
        uint256[] memory updateTimestamps = new uint256[](NUM_TOKENS);
        for (uint256 i = 0; i < NUM_TOKENS; i++) {
            answers[i] = bound(answersRaw[i], 1, MAX_UINT128);
            updateTimestamps[i] = block.timestamp - bound(updateTimestampsRaw[i], 1, 100);

            if (updateTimestamps[i] < minUpdateTimestamp) {
                minUpdateTimestamp = updateTimestamps[i];
            }
        }

        IGyroECLPPool pool = createAndInitPool();
        (EclpLPOracleMock oracle, AggregatorV3Interface[] memory feeds) = deployOracle(pool);

        for (uint256 i = 0; i < NUM_TOKENS; i++) {
            FeedMock(address(feeds[i])).setLastRoundData(answers[i], updateTimestamps[i]);
        }

        (int256[] memory returnedAnswers, uint256 returnedUpdateTimestamp) = oracle.getFeedData();
        for (uint256 i = 0; i < NUM_TOKENS; i++) {
            assertEq(
                uint256(returnedAnswers[i]),
                answers[i] * oracle.getFeedTokenDecimalScalingFactors()[i],
                "Answer does not match"
            );
        }
        assertEq(returnedUpdateTimestamp, minUpdateTimestamp, "Update timestamp does not match");
    }

    // TODO find a way to validate the TVL
    // function testCalculateTVL__Fuzz(
    //     uint256[NUM_TOKENS] memory poolInitAmountsRaw,
    //     uint256[NUM_TOKENS] memory pricesRaw
    // ) public {
    //     address[] memory _tokens = new address[](NUM_TOKENS);
    //     uint256[] memory poolInitAmounts = new uint256[](NUM_TOKENS);
    //     int256[] memory prices = new int256[](NUM_TOKENS);

    //     uint256 restWeight = FixedPoint.ONE;
    //     for (uint256 i = 0; i < NUM_TOKENS; i++) {
    //         _tokens[i] = address(sortedTokens[i]);
    //         poolInitAmounts[i] = bound(poolInitAmountsRaw[i], defaultAccountBalance() / 10, defaultAccountBalance());
    //         prices[i] = int256(bound(pricesRaw[i], FixedPoint.ONE, MAX_UINT128 / 10));
    //     }

    //     IGyroECLPPool pool = createAndInitPool(_tokens, poolInitAmounts);
    //     (EclpLPOracleMock oracle, ) = deployOracle(pool);

    //     uint256 tvl = oracle.calculateTVL(prices);

    //     uint256[] memory lastBalancesLiveScaled18 = vault.getCurrentLiveBalances(address(pool));

    //     uint256 expectedTVL = FixedPoint.ONE;
    //     for (uint256 i = 0; i < NUM_TOKENS; i++) {
    //         expectedTVL = expectedTVL.mulDown(uint256(prices[i]).divDown(weights[i]).powDown(weights[i]));
    //     }
    //     expectedTVL = expectedTVL.mulDown(pool.computeInvariant(lastBalancesLiveScaled18, Rounding.ROUND_UP));

    //     assertEq(tvl, expectedTVL, "TVL does not match");
    // }

    function testCalculateTVLAfterSwap() public {
        IGyroECLPPool pool = createAndInitPool(
            [address(dai), address(usdc)].toMemoryArray(),
            [poolInitAmount, poolInitAmount].toMemoryArray()
        );
        uint256 poolValue = 2 * poolInitAmount;

        (EclpLPOracleMock oracle, ) = deployOracle(pool);
        int256[] memory prices = [int256(1e18), int256(1e18)].toMemoryArray();

        uint256 tvlBefore = oracle.calculateTVL(prices);

        uint256 swapAmount = poolInitAmount / 10;

        vm.prank(lp);
        router.swapSingleTokenExactIn(address(pool), dai, usdc, swapAmount, 0, MAX_UINT256, false, bytes(""));

        uint256 tvlAfter = oracle.calculateTVL(prices);
        uint256 totalSupply = vault.totalSupply(address(pool));

        assertApproxEqRel(tvlAfter, tvlBefore, 1e3, "TVL should not change after swap");
        assertApproxEqRel(tvlAfter, poolValue, 1e15, "TVL should be close to the sum of assets in the pool");
    }

    function testCalculateTVLAfterSwapWithRates() public {
        address[] memory tokens = [address(usdc), address(dai)].toMemoryArray();
        IRateProvider[] memory rateProviders = new IRateProvider[](tokens.length);

        for (uint256 i = 0; i < tokens.length; i++) {
            RateProviderMock rateProvider = new RateProviderMock();
            rateProvider.mockRate(1e18 + (1 + i) * 1e17);
            rateProviders[i] = IRateProvider(address(rateProvider));
        }

        IGyroECLPPool pool = createAndInitPool(tokens, rateProviders, [poolInitAmount, poolInitAmount].toMemoryArray());

        (EclpLPOracleMock oracle, ) = deployOracle(pool);
        int256[] memory prices = [int256(1e18), int256(1e18)].toMemoryArray();

        uint256 tvlBefore = oracle.calculateTVL(prices);

        uint256 swapAmount = poolInitAmount / 10;

        vm.prank(lp);
        router.swapSingleTokenExactIn(address(pool), dai, usdc, swapAmount, 0, MAX_UINT256, false, bytes(""));

        uint256 tvlAfter = oracle.calculateTVL(prices);

        assertApproxEqRel(tvlAfter, tvlBefore, 1e3, "TVL should not change after swap");
    }

    function testLatestRoundData__Fuzz(
        uint256[NUM_TOKENS] memory poolInitAmountsRaw,
        uint256[NUM_TOKENS] memory answersRaw,
        uint256[NUM_TOKENS] memory updateTimestampsRaw
    ) public {
        address[] memory _tokens = new address[](NUM_TOKENS);
        uint256[] memory poolInitAmounts = new uint256[](NUM_TOKENS);
        uint256[] memory answers = new uint256[](NUM_TOKENS);
        uint256[] memory updateTimestamps = new uint256[](NUM_TOKENS);

        uint256 minUpdateTimestamp = MAX_UINT256;
        {
            for (uint256 i = 0; i < NUM_TOKENS; i++) {
                _tokens[i] = address(sortedTokens[i]);
                poolInitAmounts[i] = bound(
                    poolInitAmountsRaw[i],
                    defaultAccountBalance() / 10,
                    defaultAccountBalance()
                );
                // The min E-CLP price is 1e11.
                answers[i] = bound(answersRaw[i], 1e11, MAX_UINT128 / 10);
                updateTimestamps[i] = block.timestamp - bound(updateTimestampsRaw[i], 1, 100);

                if (updateTimestamps[i] < minUpdateTimestamp) {
                    minUpdateTimestamp = updateTimestamps[i];
                }
            }
        }

        IGyroECLPPool pool = createAndInitPool(_tokens, poolInitAmounts);
        (EclpLPOracleMock oracle, AggregatorV3Interface[] memory feeds) = deployOracle(pool);

        for (uint256 i = 0; i < NUM_TOKENS; i++) {
            FeedMock(address(feeds[i])).setLastRoundData(answers[i], updateTimestamps[i]);
        }

        // uint256[] memory lastBalancesLiveScaled18 = vault.getCurrentLiveBalances(address(pool));

        // uint256 expectedTVL = FixedPoint.ONE;
        // for (uint256 i = 0; i < NUM_TOKENS; i++) {
        //     uint256 price = answers[i] * oracle.getFeedTokenDecimalScalingFactors()[i];
        //     expectedTVL = expectedTVL.mulDown(uint256(price).divDown(weights[i]).powDown(weights[i]));
        // }
        // expectedTVL = expectedTVL.mulDown(pool.computeInvariant(lastBalancesLiveScaled18, Rounding.ROUND_UP));

        (
            uint80 roundId,
            int256 lpPrice,
            uint256 startedAt,
            uint256 returnedUpdateTimestamp,
            uint80 answeredInRound
        ) = oracle.latestRoundData();

        assertEq(uint256(roundId), 0, "Round ID does not match");
        // TODO find a way to validate lpPrice
        // assertEq(uint256(lpPrice), expectedTVL.divUp(IERC20(address(pool)).totalSupply()), "LP price does not match");
        assertEq(startedAt, 0, "Started at does not match");
        assertEq(returnedUpdateTimestamp, minUpdateTimestamp, "Update timestamp does not match");
        assertEq(answeredInRound, 0, "Answered in round does not match");
    }
}
