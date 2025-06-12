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
        uint256 amplificationFactor,
        uint256[MAX_TOKENS] memory poolInitAmountsRaw,
        uint256[MAX_TOKENS] memory pricesRaw
    ) public {
        totalTokens = bound(totalTokens, MIN_TOKENS, MAX_TOKENS);
        amplificationFactor = bound(amplificationFactor, StableMath.MIN_AMP, StableMath.MAX_AMP);

        address[] memory _tokens = new address[](totalTokens);
        uint256[] memory poolInitAmounts = new uint256[](totalTokens);
        uint256[] memory prices = new uint256[](totalTokens);

        for (uint256 i = 0; i < totalTokens; i++) {
            _tokens[i] = address(sortedTokens[i]);
            uint256 decimalsToken = IERC20Metadata(address(sortedTokens[i])).decimals();
            poolInitAmounts[i] = bound(
                poolInitAmountsRaw[i],
                defaultAccountBalance() / (10 ** (18 - decimalsToken + 3)),
                defaultAccountBalance() / (10 ** (18 - decimalsToken + 1))
            );
            prices[i] = bound(pricesRaw[i], 10 ** (14), 10 ** 24) / (10 ** (18 - decimalsToken));
        }

        IStablePool pool = createAndInitPool(totalTokens, amplificationFactor);
        (StableLPOracleMock oracle, AggregatorV3Interface[] memory feeds) = deployOracle(pool);

        (, , , uint256[] memory liveBalancesScaled18) = vault.getPoolTokenInfo(address(pool));
        uint256 invariant = pool.computeInvariant(liveBalancesScaled18, Rounding.ROUND_DOWN);

        int256[] memory pricesInt = new int256[](totalTokens);
        for (uint256 i = 0; i < totalTokens; i++) {
            uint256 price = prices[i] * oracle.getFeedTokenDecimalScalingFactors()[i];
            pricesInt[i] = int256(price);
        }
        uint256[] memory balancesForPricesScaled18 = oracle.computeBalancesForPrices(invariant, pricesInt);
        uint256 invariantForPrices = pool.computeInvariant(balancesForPricesScaled18, Rounding.ROUND_DOWN);

        assertEq(invariantForPrices, invariant, "Invariant does not match");
    }

    function testCalculateTVL2Tokens__Fuzz(uint256 amplificationFactor) public {
        // For a pool with 2 tokens, 1000 balance, rate = 1, the expected TVL is 2000 (the pool is balanced, so the
        // amp factor doesn't matter).
        uint256 expectedTVL = 2000e18;

        uint256 totalTokens = 2;
        amplificationFactor = bound(amplificationFactor, StableMath.MIN_AMP, StableMath.MAX_AMP);

        address[] memory _tokens = new address[](totalTokens);
        uint256[] memory poolInitAmounts = new uint256[](totalTokens);
        int256[] memory prices = new int256[](totalTokens);

        for (uint256 i = 0; i < totalTokens; i++) {
            _tokens[i] = address(sortedTokens[i]);
            uint256 decimalsToken = IERC20Metadata(address(sortedTokens[i])).decimals();
            poolInitAmounts[i] = 1000e18 / (10 ** (18 - decimalsToken));
            prices[i] = int256(FixedPoint.ONE / (10 ** (18 - decimalsToken)));
        }

        IStablePool pool = createAndInitPool(_tokens, poolInitAmounts, amplificationFactor);
        (StableLPOracleMock oracle, ) = deployOracle(pool);

        int256[] memory pricesInt = new int256[](totalTokens);
        for (uint256 i = 0; i < totalTokens; i++) {
            uint256 price = uint256(prices[i]) * oracle.getFeedTokenDecimalScalingFactors()[i];
            pricesInt[i] = int256(price);
        }
        uint256 tvl = oracle.calculateTVL(pricesInt);

        assertApproxEqRel(tvl, expectedTVL, 1e8, "TVL does not match");
    }

    function testCalculateTVL2TokensUnbalanced__Fuzz(uint256 amplificationFactor) public {
        // For a pool with 2 tokens, 1000 balance, rate = 1, the expected TVL is 2000. However, this test will
        // simulate a big swap that takes the pool out of balance, and the expected TVL should still be 2000,
        // given that the invariant is the same.
        uint256 expectedTVL = 2000e18;

        uint256 totalTokens = 2;
        amplificationFactor = bound(amplificationFactor, StableMath.MIN_AMP, StableMath.MAX_AMP);

        address[] memory _tokens = new address[](totalTokens);
        uint256[] memory poolInitAmounts = new uint256[](totalTokens);
        int256[] memory prices = new int256[](totalTokens);

        for (uint256 i = 0; i < totalTokens; i++) {
            _tokens[i] = address(sortedTokens[i]);
            uint256 decimalsToken = IERC20Metadata(address(sortedTokens[i])).decimals();
            poolInitAmounts[i] = 1000e18 / (10 ** (18 - decimalsToken));
            prices[i] = int256(FixedPoint.ONE / (10 ** (18 - decimalsToken)));
        }

        IStablePool pool = createAndInitPool(_tokens, poolInitAmounts, amplificationFactor);
        (StableLPOracleMock oracle, ) = deployOracle(pool);

        // Remove the swap fee.
        vault.manualUnsafeSetStaticSwapFeePercentage(address(pool), 0);

        // Execute a swap to try to take the pool out of balance and affect the TVL calculation.
        vm.prank(lp);
        router.swapSingleTokenExactOut(
            address(pool),
            sortedTokens[0],
            sortedTokens[1],
            poolInitAmounts[1].mulDown(99e16), // Leave only 1% of token out in the pool
            MAX_UINT256,
            MAX_UINT256,
            false,
            bytes("")
        );

        int256[] memory pricesInt = new int256[](totalTokens);
        for (uint256 i = 0; i < totalTokens; i++) {
            uint256 price = uint256(prices[i]) * oracle.getFeedTokenDecimalScalingFactors()[i];
            pricesInt[i] = int256(price);
        }
        uint256 tvl = oracle.calculateTVL(pricesInt);

        assertEq(tvl, expectedTVL, "TVL does not match");
    }

    function testCalculateTVL2TokensWithRates__Fuzz(uint256 amplificationFactor) public {
        // For a pool with 2 tokens, 1000 balance, rate = 2 and 3, the expected TVL is 4800. Since the pool doesn't
        // know what are the rates, the invariant is 2000. The oracle knows that the rate of token 1 in terms of
        // token 0 is 1.5 (3 / 2). So, the oracle will find balances in the stable invariant curve where the rate is
        // 1.5 and the invariant is 2000, which are [1200, 800]. 1200 * 2 + 800 * 3 = 4800.
        uint256 expectedTVL = 4898e18;

        uint256 totalTokens = 2;
        amplificationFactor = bound(amplificationFactor, StableMath.MIN_AMP, StableMath.MAX_AMP);

        address[] memory _tokens = new address[](totalTokens);
        uint256[] memory poolInitAmounts = new uint256[](totalTokens);
        int256[] memory prices = new int256[](totalTokens);

        for (uint256 i = 0; i < totalTokens; i++) {
            _tokens[i] = address(sortedTokens[i]);
            uint256 decimalsToken = IERC20Metadata(address(sortedTokens[i])).decimals();
            poolInitAmounts[i] = 1000e18 / (10 ** (18 - decimalsToken));
            prices[i] = int256(((i + 2) * FixedPoint.ONE) / (10 ** (18 - decimalsToken)));
        }

        IStablePool pool = createAndInitPool(_tokens, poolInitAmounts, amplificationFactor);
        (StableLPOracleMock oracle, ) = deployOracle(pool);

        int256[] memory pricesInt = new int256[](totalTokens);
        for (uint256 i = 0; i < totalTokens; i++) {
            uint256 price = uint256(prices[i]) * oracle.getFeedTokenDecimalScalingFactors()[i];
            pricesInt[i] = int256(price);
        }
        uint256 tvl = oracle.calculateTVL(pricesInt);

        // Allow an error of 0.05%.
        assertApproxEqRel(tvl, expectedTVL, 0.05e16, "TVL does not match");
    }

    function testCalculateTVL2TokensUnbalancedWithRates__Fuzz(uint256 amplificationFactor) public {
        // For a pool with 2 tokens, 1000 balance, rate = 2 and 3, the expected TVL is 4800. Since the pool doesn't
        // know what are the rates, the invariant is 2000. The oracle knows that the rate of token 1 in terms of
        // token 0 is 1.5 (3 / 2). So, the oracle will find balances in the stable invariant curve where the rate is
        // 1.5 and the invariant is 2000, which are [1200, 800]. 1200 * 2 + 800 * 3 = 4800. However, this test will
        // simulate a big swap that takes the pool out of balance, and the expected TVL should still be 4800, given
        // that the invariant is the same.
        uint256 expectedTVL = 4898e18;

        uint256 totalTokens = 2;
        amplificationFactor = bound(amplificationFactor, StableMath.MIN_AMP, StableMath.MAX_AMP);

        address[] memory _tokens = new address[](totalTokens);
        uint256[] memory poolInitAmounts = new uint256[](totalTokens);
        int256[] memory prices = new int256[](totalTokens);

        for (uint256 i = 0; i < totalTokens; i++) {
            _tokens[i] = address(sortedTokens[i]);
            uint256 decimalsToken = IERC20Metadata(address(sortedTokens[i])).decimals();
            poolInitAmounts[i] = 1000e18 / (10 ** (18 - decimalsToken));
            prices[i] = int256(((i + 2) * FixedPoint.ONE) / (10 ** (18 - decimalsToken)));
        }

        IStablePool pool = createAndInitPool(_tokens, poolInitAmounts, amplificationFactor);
        (StableLPOracleMock oracle, ) = deployOracle(pool);

        // Remove the swap fee.
        vault.manualUnsafeSetStaticSwapFeePercentage(address(pool), 0);

        // Execute a swap to try to take the pool out of balance and affect the TVL calculation.
        vm.prank(lp);
        router.swapSingleTokenExactOut(
            address(pool),
            sortedTokens[0],
            sortedTokens[1],
            poolInitAmounts[1].mulDown(99e16), // Leave only 1% of token out in the pool
            MAX_UINT256,
            MAX_UINT256,
            false,
            bytes("")
        );

        int256[] memory pricesInt = new int256[](totalTokens);
        for (uint256 i = 0; i < totalTokens; i++) {
            uint256 price = uint256(prices[i]) * oracle.getFeedTokenDecimalScalingFactors()[i];
            pricesInt[i] = int256(price);
        }
        uint256 tvl = oracle.calculateTVL(pricesInt);

        // Allow an error of 0.05%.
        assertApproxEqRel(tvl, expectedTVL, 0.05e16, "TVL does not match");
    }

    function testLatestRoundData__Fuzz(
        uint256 totalTokens,
        uint256 amplificationFactor,
        uint256[MAX_TOKENS] memory poolInitAmountsRaw,
        uint256[MAX_TOKENS] memory pricesRaw,
        uint256[MAX_TOKENS] memory updateTimestampsRaw
    ) public {
        totalTokens = bound(totalTokens, MIN_TOKENS, MAX_TOKENS);

        address[] memory _tokens = new address[](totalTokens);
        uint256[] memory poolInitAmounts = new uint256[](totalTokens);
        uint256[] memory prices = new uint256[](totalTokens);
        uint256[] memory updateTimestamps = new uint256[](totalTokens);
        amplificationFactor = bound(amplificationFactor, StableMath.MIN_AMP, StableMath.MAX_AMP);

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

        IStablePool pool = createAndInitPool(_tokens, poolInitAmounts, amplificationFactor);
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
}
