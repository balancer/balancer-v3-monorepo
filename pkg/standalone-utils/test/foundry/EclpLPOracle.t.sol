// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { ILPOracleBase } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/ILPOracleBase.sol";
import { IGyroECLPPool } from "@balancer-labs/v3-interfaces/contracts/pool-gyro/IGyroECLPPool.sol";
import { Rounding } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { GyroEclpPoolDeployer } from "@balancer-labs/v3-pool-gyro/test/foundry/utils/GyroEclpPoolDeployer.sol";
import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { SignedFixedPoint } from "@balancer-labs/v3-pool-gyro/contracts/lib/SignedFixedPoint.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { RateProviderMock } from "@balancer-labs/v3-vault/contracts/test/RateProviderMock.sol";
import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { GyroECLPMath } from "@balancer-labs/v3-pool-gyro/contracts/lib/GyroECLPMath.sol";
import { GyroECLPPool } from "@balancer-labs/v3-pool-gyro/contracts/GyroECLPPool.sol";

import { EclpLPOracleMock } from "../../contracts/test/EclpLPOracleMock.sol";
import { FeedMock } from "../../contracts/test/FeedMock.sol";

contract EclpLPOracleTest is BaseVaultTest, GyroEclpPoolDeployer {
    using CastingHelpers for address[];
    using SignedFixedPoint for int256;
    using FixedPoint for uint256;
    using ArrayHelpers for *;
    using SafeCast for *;

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

        (int256[] memory returnedAnswers, uint256[] memory returnedTimestamps, uint256 minTimestamp) = oracle
            .getFeedData();
        for (uint256 i = 0; i < NUM_TOKENS; i++) {
            assertEq(
                uint256(returnedAnswers[i]),
                answers[i] * oracle.getFeedTokenDecimalScalingFactors()[i],
                "Answer does not match"
            );
            assertEq(returnedTimestamps[i], updateTimestamps[i], "Timestamp does not match");
        }
        assertEq(minTimestamp, minUpdateTimestamp, "Update timestamp does not match");
    }

    function testCalculateTVL__Fuzz(
        uint256[NUM_TOKENS] memory poolInitAmountsRaw,
        uint256[NUM_TOKENS] memory pricesRaw
    ) public {
        address[] memory _tokens = new address[](NUM_TOKENS);
        uint256[] memory poolInitAmounts = new uint256[](NUM_TOKENS);
        int256[] memory prices = new int256[](NUM_TOKENS);

        for (uint256 i = 0; i < NUM_TOKENS; i++) {
            _tokens[i] = address(sortedTokens[i]);
            poolInitAmounts[i] = bound(poolInitAmountsRaw[i], 1e18, defaultAccountBalance() / 100);
        }

        // The relative prices of the tokens must be in the range [alpha, beta].
        pricesRaw[1] = bound(pricesRaw[1], FixedPoint.ONE, MAX_UINT128 / 10);
        prices[1] = int256(pricesRaw[1]);
        pricesRaw[0] = bound(
            pricesRaw[0],
            pricesRaw[1].mulDown(uint256(_paramsAlpha)),
            pricesRaw[1].mulDown(uint256(_paramsBeta))
        );
        prices[0] = int256(pricesRaw[0]);

        IGyroECLPPool pool = createAndInitPool(_tokens, poolInitAmounts);
        (EclpLPOracleMock oracle, ) = deployOracle(pool);

        uint256 tvl = oracle.calculateTVL(prices);
        uint256 expectedTVL = _computeExpectedTVLBinarySearch(GyroECLPPool(address(pool)), pricesRaw.toMemoryArray());

        assertApproxEqRel(tvl, expectedTVL, 1e8, "TVL does not match");
    }

    function testCalculateTVLAfterSwapRateProvider() public {
        // wstETH/USDC pool, with a rate provider wstETH/ETH and oracle ETH/USD.
        // Price interval: [3100, 4400]
        // Peak liquidity price: ~3700
        // Expected TVL = 7400 => 3700 USDC + (1/[wstETH_ETH rate]) * [wstETH_ETH rate] * [ETH_USDC rate] = 7400 USD
        uint256 expectedTvlUSD = 7400e18;

        _paramsAlpha = 3100000000000000000000;
        _paramsBeta = 4400000000000000000000;
        _paramsC = 266047486094289;
        _paramsS = 999999964609366945;
        _paramsLambda = 20000000000000000000000;

        _tauAlphaX = -74906290317688179576634216999624376320;
        _tauAlphaY = 66249888081733509000774146899805470720;
        _tauBetaX = 61281617359500194184092230363650195456;
        _tauBetaY = 79022549780450675665143872372290355200;
        _u = 36232449191667728242196851875381248;
        _v = 79022548876385507382975597793964457984;
        _w = 3398134415414380205616296112422912;
        _z = -74906280678135835754217861217519665152;
        _dSq = 99999999999999997748809823456034029568;

        uint256 _WSTETH_RATE = 1.2e18;
        uint256 _ETH_USD_RATE = 3700e18;
        uint256 _INITIAL_WSTETH_BALANCE = uint256(1e18).divDown(_WSTETH_RATE);
        uint256 _INITIAL_USDC_BALANCE = _ETH_USD_RATE;

        IRateProvider[] memory rateProviders = new IRateProvider[](2);
        rateProviders[0] = IRateProvider(address(new RateProviderMock()));
        RateProviderMock(address(rateProviders[0])).mockRate(_WSTETH_RATE);

        IGyroECLPPool pool = createAndInitPool(
            [address(wsteth), address(usdc)].toMemoryArray(),
            rateProviders,
            [_INITIAL_WSTETH_BALANCE, _INITIAL_USDC_BALANCE].toMemoryArray()
        );

        (EclpLPOracleMock oracle, ) = deployOracle(pool);
        int256[] memory prices = [int256(_ETH_USD_RATE), int256(1e18)].toMemoryArray();

        uint256 tvlBefore = oracle.calculateTVL(prices);

        // Big swap, to make sure the pool is very unbalanced when computing the new TVL.
        uint256 swapAmount = _INITIAL_WSTETH_BALANCE / 3;

        vm.prank(lp);
        router.swapSingleTokenExactIn(address(pool), wsteth, usdc, swapAmount, 0, MAX_UINT256, false, bytes(""));

        uint256 tvlAfter = oracle.calculateTVL(prices);

        // Error tolerance of 0.00000001%.
        assertApproxEqRel(tvlAfter, tvlBefore, 1e8, "TVL should not change after swap");
        // For expected TVL comparison, the tolerance is bigger: 0.01% error.
        assertApproxEqRel(tvlAfter, expectedTvlUSD, 1e14, "TVL should be close to expected");
    }

    function testCalculateTVLComparingWithMarketPriceBalances() public {
        // This test compares the oracle price with the market price balance prices. The market price balances are
        // found by searching what are the balances of the pool, in the current invariant, that would be priced the
        // same as the oracle. Usually we would compute the gradient of the invariant function and compare with the
        // oracle prices, but here in the test we use a binary search to find the correct market price balances.

        // wstETH/USDC pool, with a rate provider wstETH/ETH and oracle ETH/USD.
        // Price interval: [3100, 4400]
        // Peak liquidity price: ~3700

        _paramsAlpha = 3100000000000000000000;
        _paramsBeta = 4400000000000000000000;
        _paramsC = 266047486094289;
        _paramsS = 999999964609366945;
        _paramsLambda = 20000000000000000000000;

        _tauAlphaX = -74906290317688179576634216999624376320;
        _tauAlphaY = 66249888081733509000774146899805470720;
        _tauBetaX = 61281617359500194184092230363650195456;
        _tauBetaY = 79022549780450675665143872372290355200;
        _u = 36232449191667728242196851875381248;
        _v = 79022548876385507382975597793964457984;
        _w = 3398134415414380205616296112422912;
        _z = -74906280678135835754217861217519665152;
        _dSq = 99999999999999997748809823456034029568;

        uint256 _WSTETH_RATE = 1.2e18;
        uint256 _ETH_USD_RATE = 3700e18;
        uint256 _INITIAL_WSTETH_BALANCE = uint256(1e18).divDown(_WSTETH_RATE);
        uint256 _INITIAL_USDC_BALANCE = _ETH_USD_RATE;

        IRateProvider[] memory rateProviders = new IRateProvider[](2);
        rateProviders[0] = IRateProvider(address(new RateProviderMock()));
        RateProviderMock(address(rateProviders[0])).mockRate(_WSTETH_RATE);

        IGyroECLPPool pool = createAndInitPool(
            [address(wsteth), address(usdc)].toMemoryArray(),
            rateProviders,
            [_INITIAL_WSTETH_BALANCE, _INITIAL_USDC_BALANCE].toMemoryArray()
        );

        (EclpLPOracleMock oracle, ) = deployOracle(pool);
        int256[] memory prices = [int256(_ETH_USD_RATE), int256(1e18)].toMemoryArray();

        // Big swap, to make sure the pool is very unbalanced when computing the new TVL.
        uint256 swapAmount = _INITIAL_WSTETH_BALANCE / 3;

        vm.prank(lp);
        router.swapSingleTokenExactIn(address(pool), wsteth, usdc, swapAmount, 0, MAX_UINT256, false, bytes(""));

        uint256 tvlOracle = oracle.calculateTVL(prices);
        uint256 tvlMarketPriceBalances = _computeExpectedTVLBinarySearch(
            GyroECLPPool(address(pool)),
            [_ETH_USD_RATE, uint256(1e18)].toMemoryArray()
        );

        // Error tolerance of 0.000001%.
        assertApproxEqRel(tvlOracle, tvlMarketPriceBalances, 1e10, "TVL should not change after swap");
    }

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
                poolInitAmounts[i] = bound(poolInitAmountsRaw[i], 1e18, defaultAccountBalance() / 100);

                updateTimestamps[i] = block.timestamp - bound(updateTimestampsRaw[i], 1, 100);

                if (updateTimestamps[i] < minUpdateTimestamp) {
                    minUpdateTimestamp = updateTimestamps[i];
                }
            }
        }

        // The price of the oracle needs to be within pool range.
        answers[0] = bound(answersRaw[0], uint256(_paramsAlpha), uint256(_paramsBeta));
        answers[1] = 1e18;

        IGyroECLPPool pool = createAndInitPool(_tokens, poolInitAmounts);
        (EclpLPOracleMock oracle, AggregatorV3Interface[] memory feeds) = deployOracle(pool);

        for (uint256 i = 0; i < NUM_TOKENS; i++) {
            FeedMock(address(feeds[i])).setLastRoundData(answers[i], updateTimestamps[i]);
        }

        uint256 expectedTVL = _computeExpectedTVLBinarySearch(GyroECLPPool(address(pool)), answers);

        (
            uint80 roundId,
            int256 lpPrice,
            uint256 startedAt,
            uint256 returnedUpdateTimestamp,
            uint80 answeredInRound
        ) = oracle.latestRoundData();

        assertEq(uint256(roundId), 0, "Round ID does not match");
        // Error tolerance of 0.1%.
        assertApproxEqRel(
            uint256(lpPrice),
            expectedTVL.divUp(IERC20(address(pool)).totalSupply()),
            1e15,
            "LP price does not match"
        );
        assertEq(startedAt, 0, "Started at does not match");
        assertEq(returnedUpdateTimestamp, minUpdateTimestamp, "Update timestamp does not match");
        assertEq(answeredInRound, 0, "Answered in round does not match");
    }

    function _computeExpectedTVLBinarySearch(
        GyroECLPPool pool,
        uint256[] memory oraclePricesScaled18
    ) private returns (uint256 expectedTVL) {
        uint256 snapshotId = vm.snapshot();
        uint256[] memory marketPriceBalances = _findBalancesForPrices(
            GyroECLPPool(address(pool)),
            oraclePricesScaled18[0].divDown(oraclePricesScaled18[1])
        );
        vm.revertTo(snapshotId);

        return
            marketPriceBalances[0].mulDown(oraclePricesScaled18[0]) +
            marketPriceBalances[1].mulDown(oraclePricesScaled18[1]);
    }

    function _findBalancesForPrices(
        GyroECLPPool pool,
        uint256 oraclePrice
    ) private returns (uint256[] memory marketPriceBalances) {
        IERC20[] memory tokens;
        uint256[] memory balancesRaw;
        (tokens, , balancesRaw, marketPriceBalances) = vault.getPoolTokenInfo(address(pool));

        (IGyroECLPPool.EclpParams memory eclpParams, IGyroECLPPool.DerivedEclpParams memory derivedEclpParams) = pool
            .getECLPParams();

        uint256 limitTokenABalance = uint256(0);
        uint256 limitTokenBBalance = uint256(0);

        for (uint256 i = 0; i < 255; i++) {
            (int256 a, int256 b) = _computeOffsetFromBalances(marketPriceBalances, eclpParams, derivedEclpParams);
            uint256 price = _computePrice(marketPriceBalances, eclpParams, a, b);

            if (
                (price > oraclePrice && (price - oraclePrice).divDown(oraclePrice) < 1e6) ||
                (price < oraclePrice && (oraclePrice - price).divDown(oraclePrice) < 1e6)
            ) {
                return marketPriceBalances;
            }

            if (price > oraclePrice) {
                // Overpriced (more B than A) => Swap A for B, exact out
                uint256 exactAmountOut = (balancesRaw[1] - limitTokenBBalance) / 2;
                limitTokenABalance = balancesRaw[0];

                vm.prank(lp);
                router.swapSingleTokenExactOut(
                    address(pool),
                    tokens[0],
                    tokens[1],
                    exactAmountOut,
                    MAX_UINT256,
                    MAX_UINT256,
                    false,
                    bytes("")
                );

                (, , balancesRaw, marketPriceBalances) = vault.getPoolTokenInfo(address(pool));
            } else {
                // Underpriced (more A than B) => Swap B for A, exact out
                uint256 exactAmountOut = (balancesRaw[0] - limitTokenABalance) / 2;
                limitTokenBBalance = balancesRaw[1];

                vm.prank(lp);
                router.swapSingleTokenExactOut(
                    address(pool),
                    tokens[1],
                    tokens[0],
                    exactAmountOut,
                    MAX_UINT256,
                    MAX_UINT256,
                    false,
                    bytes("")
                );

                (, , balancesRaw, marketPriceBalances) = vault.getPoolTokenInfo(address(pool));
            }
        }

        revert("Could not find market balances");
    }

    function _computePrice(
        uint256[] memory balancesScaled18,
        IGyroECLPPool.EclpParams memory eclpParams,
        int256 a,
        int256 b
    ) internal pure returns (uint256 price) {
        // To compute the price, first we need to transform the real balances into balances of a circle centered at
        // (0,0).
        //
        // The transformation is:
        //
        //     --   --    --                     --   --     --
        //     | x'' |    |  c/lambda  -s/lambda  | * | x - a |
        //     | y'' | =  |     s          c      |   | y - b |
        //     --   --    --                     --   --     --
        //
        // With x'' and y'', we can compute the price as:
        //
        //                          --              --   --   --
        //             [xll, yll] o |  c/lambda   s  | * |  1  |
        //                          | -s/lambda   c  |   |  0  |
        //                          --              --   --   --
        //    price =  -------------------------------------------
        //                          --              --   --   --
        //             [xll, yll] o |  c/lambda   s  | * |  0  |
        //                          | -s/lambda   c  |   |  1  |
        //                          --              --   --   --

        // Balances in the rotated ellipse centered at (0,0)
        int256 xl = int256(balancesScaled18[0]) - a;
        int256 yl = int256(balancesScaled18[1]) - b;

        // Balances in the circle centered at (0,0)
        int256 xll = xl.mulDownMag(eclpParams.c).divDownMag(eclpParams.lambda) -
            yl.mulDownMag(eclpParams.s).divDownMag(eclpParams.lambda);
        int256 yll = xl.mulDownMag(eclpParams.s) + yl.mulDownMag(eclpParams.c);

        // Scalar product of [xll, yll] by A*[1,0] => e_x (unity vector in the x direction).
        int256 numerator = xll.mulDownMag(eclpParams.c).divDownMag(eclpParams.lambda) + yll.mulDownMag(eclpParams.s);
        // Scalar product of [xll, yll] by A*[0,1] => e_y (unity vector in the y direction).
        int256 denominator = yll.mulDownMag(eclpParams.c) - xll.mulDownMag(eclpParams.s).divDownMag(eclpParams.lambda);

        price = numerator.divDownMag(denominator).toUint256();

        // The price cannot be outside of pool range.
        if (price < eclpParams.alpha.toUint256()) {
            price = eclpParams.alpha.toUint256();
        } else if (price > eclpParams.beta.toUint256()) {
            price = eclpParams.beta.toUint256();
        }

        return price;
    }

    function _computeOffsetFromBalances(
        uint256[] memory balancesScaled18,
        IGyroECLPPool.EclpParams memory eclpParams,
        IGyroECLPPool.DerivedEclpParams memory derivedECLPParams
    ) internal pure returns (int256 a, int256 b) {
        IGyroECLPPool.Vector2 memory invariant;

        {
            (int256 currentInvariant, int256 invErr) = GyroECLPMath.calculateInvariantWithError(
                balancesScaled18,
                eclpParams,
                derivedECLPParams
            );
            // invariant = overestimate in x-component, underestimate in y-component
            // No overflow in `+` due to constraints to the different values enforced in GyroECLPMath.
            invariant = IGyroECLPPool.Vector2(currentInvariant + 2 * invErr, currentInvariant);
        }

        a = GyroECLPMath.virtualOffset0(eclpParams, derivedECLPParams, invariant);
        b = GyroECLPMath.virtualOffset1(eclpParams, derivedECLPParams, invariant);
    }
}
