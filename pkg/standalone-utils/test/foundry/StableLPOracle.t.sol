// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { PoolRoleAccounts, Rounding } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IStablePool } from "@balancer-labs/v3-interfaces/contracts/pool-stable/IStablePool.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { StablePoolFactory } from "@balancer-labs/v3-pool-stable/contracts/StablePoolFactory.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { StableMath } from "@balancer-labs/v3-solidity-utils/contracts/math/StableMath.sol";
import {
    StablePoolContractsDeployer
} from "@balancer-labs/v3-pool-stable/test/foundry/utils/StablePoolContractsDeployer.sol";

import { StableLPOracleMock } from "../../contracts/test/StableLPOracleMock.sol";
import { FeedMock } from "../../contracts/test/FeedMock.sol";

contract StableLPOracleTest is BaseVaultTest, StablePoolContractsDeployer {
    using FixedPoint for uint256;
    using CastingHelpers for address[];
    using ArrayHelpers for *;

    uint256 constant VERSION = 123;
    uint256 constant MAX_TOKENS = 5;
    uint256 constant MIN_TOKENS = 2;

    event Log(address indexed value);
    event LogUint(uint256 indexed value);

    IERC20[] sortedTokens;

    StablePoolFactory stablePoolFactory;
    uint256 poolCreationNonce;

    function setUp() public virtual override {
        for (uint256 i = 0; i < MAX_TOKENS; i++) {
            tokens.push(createERC20(string(abi.encodePacked("TK", i)), 18 - uint8(2 * i)));
        }

        sortedTokens = InputHelpers.sortTokens(tokens);

        super.setUp();

        stablePoolFactory = deployStablePoolFactory(IVault(address(vault)), 365 days, "Factory v1", "Pool v1");
    }

    function deployOracle(
        IStablePool pool
    ) internal returns (StableLPOracleMock oracle, AggregatorV3Interface[] memory feeds) {
        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(address(pool));

        feeds = new AggregatorV3Interface[](tokens.length);

        for (uint256 i = 0; i < tokens.length; i++) {
            feeds[i] = AggregatorV3Interface(address(new FeedMock(IERC20Metadata(address(tokens[i])).decimals())));
        }

        oracle = new StableLPOracleMock(IVault(address(vault)), pool, feeds, VERSION);
    }

    function createAndInitPool() internal returns (IStablePool) {
        IStablePool pool = createAndInitPool(2, 100);
        return pool;
    }

    function createAndInitPool(uint256 totalTokens, uint256 amplificationParameter) internal returns (IStablePool) {
        address[] memory _tokens = new address[](totalTokens);
        uint256[] memory poolInitAmounts = new uint256[](totalTokens);

        for (uint256 i = 0; i < totalTokens; i++) {
            _tokens[i] = address(sortedTokens[i]);
            poolInitAmounts[i] = poolInitAmount;
        }

        return (createAndInitPool(_tokens, poolInitAmounts, amplificationParameter));
    }

    function createAndInitPool(
        address[] memory _tokens,
        uint256[] memory initAmounts,
        uint256 amplificationParameter
    ) internal returns (IStablePool) {
        string memory name = "Stable Pool Test";
        string memory symbol = "STABLE-TEST";

        PoolRoleAccounts memory roleAccounts;

        address newPool = stablePoolFactory.create(
            name,
            symbol,
            vault.buildTokenConfig(_tokens.asIERC20()),
            amplificationParameter,
            roleAccounts,
            DEFAULT_SWAP_FEE_PERCENTAGE,
            address(0),
            true,
            false,
            bytes32(poolCreationNonce++)
        );

        vm.startPrank(lp);
        _initPool(newPool, initAmounts, 0);
        vm.stopPrank();

        return IStablePool(newPool);
    }

    function testDecimals() public {
        IStablePool pool = createAndInitPool();
        (StableLPOracleMock oracle, ) = deployOracle(pool);

        assertEq(oracle.decimals(), 18, "Decimals does not match");
    }

    function testVersion() public {
        IStablePool pool = createAndInitPool();
        (StableLPOracleMock oracle, ) = deployOracle(pool);

        assertEq(oracle.version(), VERSION, "Version does not match");
    }

    function testDescription() public {
        IStablePool pool = createAndInitPool();
        (StableLPOracleMock oracle, ) = deployOracle(pool);

        assertEq(oracle.description(), "STABLE-TEST/USD", "Description does not match");
    }

    function testGetFeeds__Fuzz(uint256 totalTokens) public {
        totalTokens = bound(totalTokens, MIN_TOKENS, MAX_TOKENS);

        IStablePool pool = createAndInitPool(totalTokens, 100);

        (StableLPOracleMock oracle, AggregatorV3Interface[] memory feeds) = deployOracle(pool);

        AggregatorV3Interface[] memory returnedFeeds = oracle.getFeeds();

        assertEq(feeds.length, returnedFeeds.length, "Feeds length does not match");

        for (uint256 i = 0; i < feeds.length; i++) {
            assertEq(address(feeds[i]), address(returnedFeeds[i]), "Feed does not match");
        }
    }

    function testGetFeedTokenDecimalScalingFactors__Fuzz(uint256 totalTokens) public {
        totalTokens = bound(totalTokens, MIN_TOKENS, MAX_TOKENS);

        IStablePool pool = createAndInitPool(totalTokens, 100);

        (StableLPOracleMock oracle, AggregatorV3Interface[] memory feeds) = deployOracle(pool);

        uint256[] memory returnedScalingFactors = oracle.getFeedTokenDecimalScalingFactors();

        for (uint256 i = 0; i < feeds.length; i++) {
            assertEq(
                oracle.calculateFeedTokenDecimalScalingFactor(feeds[i]),
                returnedScalingFactors[i],
                "Scaling factor does not match"
            );
        }
    }

    function testCalculateFeedTokenDecimalScalingFactor__Fuzz(uint256 totalTokens) public {
        totalTokens = bound(totalTokens, MIN_TOKENS, MAX_TOKENS);

        IStablePool pool = createAndInitPool(totalTokens, 100);
        (StableLPOracleMock oracle, AggregatorV3Interface[] memory feeds) = deployOracle(pool);

        for (uint256 i = 0; i < feeds.length; i++) {
            assertEq(
                oracle.calculateFeedTokenDecimalScalingFactor(feeds[i]),
                10 ** (18 - IERC20Metadata(address(feeds[i])).decimals()),
                "Scaling factor does not match"
            );
        }
    }

    function testGetFeedData__Fuzz(
        uint256 totalTokens,
        uint256[MAX_TOKENS] memory answersRaw,
        uint256[MAX_TOKENS] memory updateTimestampsRaw
    ) public {
        totalTokens = bound(totalTokens, MIN_TOKENS, MAX_TOKENS);

        uint256 minUpdateTimestamp = MAX_UINT256;
        uint256[] memory answers = new uint256[](totalTokens);
        uint256[] memory updateTimestamps = new uint256[](totalTokens);
        for (uint256 i = 0; i < totalTokens; i++) {
            answers[i] = bound(answersRaw[i], 1, MAX_UINT128);
            updateTimestamps[i] = block.timestamp - bound(updateTimestampsRaw[i], 1, 100);

            if (updateTimestamps[i] < minUpdateTimestamp) {
                minUpdateTimestamp = updateTimestamps[i];
            }
        }

        IStablePool pool = createAndInitPool(totalTokens, 100);
        (StableLPOracleMock oracle, AggregatorV3Interface[] memory feeds) = deployOracle(pool);

        for (uint256 i = 0; i < totalTokens; i++) {
            FeedMock(address(feeds[i])).setLastRoundData(answers[i], updateTimestamps[i]);
        }

        (int256[] memory returnedAnswers, uint256 returnedUpdateTimestamp) = oracle.getFeedData();
        for (uint256 i = 0; i < totalTokens; i++) {
            assertEq(
                uint256(returnedAnswers[i]),
                answers[i] * oracle.getFeedTokenDecimalScalingFactors()[i],
                "Answer does not match"
            );
        }
        assertEq(returnedUpdateTimestamp, minUpdateTimestamp, "Update timestamp does not match");
    }

    function testComputeBalancesForPrices__Fuzz(
        uint256 totalTokens,
        uint256 amplificationParameter,
        uint256[MAX_TOKENS] memory poolInitAmountsRaw,
        uint256[MAX_TOKENS] memory pricesRaw
    ) public {
        totalTokens = bound(totalTokens, MIN_TOKENS, MAX_TOKENS);
        amplificationParameter = bound(amplificationParameter, StableMath.MIN_AMP, 1);

        uint256[] memory prices = new uint256[](totalTokens);
        int256[] memory pricesEqual = new int256[](totalTokens);
        int256[] memory pricesInt = new int256[](totalTokens);
        IStablePool pool;
        StableLPOracleMock oracle;
        {
            uint256[] memory poolInitAmounts = new uint256[](totalTokens);
            address[] memory _tokens = new address[](totalTokens);
            for (uint256 i = 0; i < totalTokens; i++) {
                _tokens[i] = address(sortedTokens[i]);
                uint256 decimalsToken = IERC20Metadata(address(sortedTokens[i])).decimals();
                poolInitAmounts[i] = bound(
                    poolInitAmountsRaw[i],
                    defaultAccountBalance() / (10 ** (18 - decimalsToken + 3)),
                    defaultAccountBalance() / (10 ** (18 - decimalsToken + 1))
                );
                prices[i] = bound(pricesRaw[i], 10 ** (17), 10 ** 19) / (10 ** (18 - decimalsToken));
                pricesEqual[i] = int256(FixedPoint.ONE);
                uint256 price = prices[i] * (10 ** (18 - decimalsToken));
                pricesInt[i] = int256(price);
            }

            pool = createAndInitPool(_tokens, poolInitAmounts, amplificationParameter);
            (oracle, ) = deployOracle(pool);
        }

        // This test reproduces the `calculateTVL` function.

        uint256 D = _getInvariant(amplificationParameter * StableMath.AMP_PRECISION, address(pool));

        uint256[] memory balancesForPricesScaled18 = oracle.computeBalancesForPrices(D, pricesEqual);

        uint256 smallestD = StableMath.computeInvariant(
            amplificationParameter * StableMath.AMP_PRECISION,
            balancesForPricesScaled18
        );

        if (D < smallestD) {
            smallestD = D;
        }

        balancesForPricesScaled18 = oracle.computeBalancesForPrices(smallestD, pricesInt);

        _checkPricesAndInvariant(amplificationParameter, balancesForPricesScaled18, smallestD, totalTokens, pricesInt);
    }

    function testCalculateTVL2Tokens__Fuzz(uint256 amplificationParameter) public {
        // For a pool with 2 tokens, 1000 balance, rate = 1, the expected TVL is 2000 (the pool is balanced, so the
        // amp factor doesn't matter).
        uint256 expectedTVL = 2000e18;

        uint256 totalTokens = 2;
        amplificationParameter = bound(amplificationParameter, StableMath.MIN_AMP, StableMath.MAX_AMP);

        address[] memory _tokens = new address[](totalTokens);
        uint256[] memory poolInitAmounts = new uint256[](totalTokens);
        int256[] memory prices = new int256[](totalTokens);

        for (uint256 i = 0; i < totalTokens; i++) {
            _tokens[i] = address(sortedTokens[i]);
            uint256 decimalsToken = IERC20Metadata(address(sortedTokens[i])).decimals();
            poolInitAmounts[i] = 1000e18 / (10 ** (18 - decimalsToken));
            prices[i] = int256(FixedPoint.ONE / (10 ** (18 - decimalsToken)));
        }

        IStablePool pool = createAndInitPool(_tokens, poolInitAmounts, amplificationParameter);
        (StableLPOracleMock oracle, ) = deployOracle(pool);

        int256[] memory pricesInt = new int256[](totalTokens);
        for (uint256 i = 0; i < totalTokens; i++) {
            uint256 price = uint256(prices[i]) * oracle.getFeedTokenDecimalScalingFactors()[i];
            pricesInt[i] = int256(price);
        }
        uint256 tvl = oracle.calculateTVL(pricesInt);

        assertApproxEqRel(tvl, expectedTVL, 1e8, "TVL does not match");

        (, , , uint256[] memory liveBalancesScaled18) = vault.getPoolTokenInfo(address(pool));
        uint256 invariant = pool.computeInvariant(liveBalancesScaled18, Rounding.ROUND_DOWN);

        uint256[] memory balancesForPricesScaled18 = oracle.computeBalancesForPrices(invariant, pricesInt);
        uint256 invariantForPrices = pool.computeInvariant(balancesForPricesScaled18, Rounding.ROUND_DOWN);

        assertApproxEqRel(invariantForPrices, invariant, 1e4, "Invariant does not match");
    }

    function testLatestRoundData__Fuzz(
        uint256 totalTokens,
        uint256 amplificationParameter,
        uint256[MAX_TOKENS] memory poolInitAmountsRaw,
        uint256[MAX_TOKENS] memory pricesRaw,
        uint256[MAX_TOKENS] memory updateTimestampsRaw
    ) public {
        totalTokens = bound(totalTokens, MIN_TOKENS, MAX_TOKENS);

        address[] memory _tokens = new address[](totalTokens);
        uint256[] memory poolInitAmounts = new uint256[](totalTokens);
        uint256[] memory prices = new uint256[](totalTokens);
        uint256[] memory updateTimestamps = new uint256[](totalTokens);
        amplificationParameter = bound(amplificationParameter, StableMath.MIN_AMP, StableMath.MAX_AMP);

        uint256 minUpdateTimestamp = MAX_UINT256;
        {
            for (uint256 i = 0; i < totalTokens; i++) {
                _tokens[i] = address(sortedTokens[i]);
                uint256 decimalsToken = IERC20Metadata(address(sortedTokens[i])).decimals();
                poolInitAmounts[i] = bound(
                    poolInitAmountsRaw[i],
                    defaultAccountBalance() / (10 ** (18 - decimalsToken + 3)),
                    defaultAccountBalance() / (10 ** (18 - decimalsToken + 1))
                );
                prices[i] = bound(pricesRaw[i], 10 ** (14), 10 ** 24) / (10 ** (18 - decimalsToken));
                updateTimestamps[i] = block.timestamp - bound(updateTimestampsRaw[i], 1, 100);

                if (updateTimestamps[i] < minUpdateTimestamp) {
                    minUpdateTimestamp = updateTimestamps[i];
                }
            }
        }

        IStablePool pool = createAndInitPool(_tokens, poolInitAmounts, amplificationParameter);
        (StableLPOracleMock oracle, AggregatorV3Interface[] memory feeds) = deployOracle(pool);

        for (uint256 i = 0; i < totalTokens; i++) {
            FeedMock(address(feeds[i])).setLastRoundData(prices[i], updateTimestamps[i]);
        }

        int256[] memory pricesInt = new int256[](totalTokens);
        for (uint256 i = 0; i < totalTokens; i++) {
            uint256 price = prices[i] * oracle.getFeedTokenDecimalScalingFactors()[i];
            pricesInt[i] = int256(price);
        }
        uint256 expectedTVL = oracle.calculateTVL(pricesInt);

        (
            uint80 roundId,
            int256 lpPrice,
            uint256 startedAt,
            uint256 returnedUpdateTimestamp,
            uint80 answeredInRound
        ) = oracle.latestRoundData();

        assertEq(uint256(roundId), 0, "Round ID does not match");
        assertEq(uint256(lpPrice), expectedTVL.divUp(IERC20(address(pool)).totalSupply()), "LP price does not match");
        assertEq(startedAt, 0, "Started at does not match");
        assertEq(returnedUpdateTimestamp, minUpdateTimestamp, "Update timestamp does not match");
        assertEq(answeredInRound, 0, "Answered in round does not match");
    }

    function _checkPricesAndInvariant(
        uint256 amplificationParameter,
        uint256[] memory balancesForPricesScaled18,
        uint256 smallestD,
        uint256 totalTokens,
        int256[] memory prices
    ) private pure {
        uint256 newD = StableMath.computeInvariant(
            amplificationParameter * StableMath.AMP_PRECISION,
            balancesForPricesScaled18
        );

        for (uint256 i = 0; i < totalTokens; i++) {
            balancesForPricesScaled18[i] = (balancesForPricesScaled18[i] * smallestD) / newD;
        }

        newD = StableMath.computeInvariant(
            amplificationParameter * StableMath.AMP_PRECISION,
            balancesForPricesScaled18
        );

        assertApproxEqAbs(smallestD, newD, 5, "Invariant does not match");

        uint256 amountInScaled18 = balancesForPricesScaled18[0].mulDown(0.001e18); // 0.1% of first token balance.
        for (uint256 i = 1; i < totalTokens; i++) {
            // Even though python finds the right prices, and the balances found by solidity are virtually the same
            // found in the python script, the solidity version of the computeOutGivenExactIn has some imprecision
            // and the prices don't match.
            uint256 amountOutScaled18 = StableMath.computeOutGivenExactIn(
                amplificationParameter * StableMath.AMP_PRECISION,
                balancesForPricesScaled18,
                0,
                i,
                amountInScaled18,
                newD
            );
            assertEq(
                uint256(prices[0]).mulDown(amountInScaled18).divDown(amountOutScaled18),
                uint256(prices[i]),
                "Price does not match"
            );
        }
    }

    function _getInvariant(uint256 amplificationParameter, address pool) private view returns (uint256 invariant) {
        (, , , uint256[] memory liveBalancesScaled18) = vault.getPoolTokenInfo(pool);
        invariant = StableMath.computeInvariant(amplificationParameter, liveBalancesScaled18);
    }
}
