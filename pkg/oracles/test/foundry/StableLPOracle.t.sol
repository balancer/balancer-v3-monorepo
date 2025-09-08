// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { ISequencerUptimeFeed } from "@balancer-labs/v3-interfaces/contracts/oracles/ISequencerUptimeFeed.sol";
import { PoolRoleAccounts, Rounding } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { ILPOracleBase } from "@balancer-labs/v3-interfaces/contracts/oracles/ILPOracleBase.sol";
import { IStablePool } from "@balancer-labs/v3-interfaces/contracts/pool-stable/IStablePool.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { StablePoolFactory } from "@balancer-labs/v3-pool-stable/contracts/StablePoolFactory.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { StableMath } from "@balancer-labs/v3-solidity-utils/contracts/math/StableMath.sol";
import {
    StablePoolContractsDeployer
} from "@balancer-labs/v3-pool-stable/test/foundry/utils/StablePoolContractsDeployer.sol";

import { StableLPOracleMock } from "../../contracts/test/StableLPOracleMock.sol";
import { StableLPOracle } from "../../contracts/StableLPOracle.sol";
import { BaseLPOracleTest } from "./utils/BaseLPOracleTest.sol";
import { FeedMock } from "../../contracts/test/FeedMock.sol";

contract StableLPOracleTest is BaseLPOracleTest, StablePoolContractsDeployer {
    using CastingHelpers for address[];
    using FixedPoint for uint256;
    using ArrayHelpers for *;

    uint256 constant MAX_TOKENS = 5;

    uint256 constant MAX_PRICE = 1e30;
    uint256 constant MIN_PRICE = 1e10;

    uint256 constant PRICE_RATIO_LIMIT = 1e7;

    event Log(address indexed value);
    event LogUint(uint256 indexed value);

    IERC20[] internal tokens18;
    IERC20[] internal sortedTokens18;

    StablePoolFactory stablePoolFactory;
    uint256 poolCreationNonce;

    function setUp() public virtual override {
        for (uint256 i = 0; i < MAX_TOKENS; i++) {
            tokens18.push(createERC20(string(abi.encodePacked("TK18-", i)), 18));
        }

        sortedTokens18 = InputHelpers.sortTokens(tokens18);

        super.setUp();

        stablePoolFactory = deployStablePoolFactory(IVault(address(vault)), 365 days, "Factory v1", "Pool v1");

        for (uint256 i = 0; i < users.length; ++i) {
            address user = users[i];

            vm.startPrank(user);
            for (uint256 j = 0; j < tokens18.length; ++j) {
                deal(address(tokens18[j]), user, defaultAccountBalance());
                tokens18[j].approve(address(permit2), type(uint256).max);
                permit2.approve(address(tokens18[j]), address(router), type(uint160).max, type(uint48).max);
            }
            vm.stopPrank();
        }
    }

    // From BaseLPOracleTest
    function getMaxTokens() public pure override returns (uint256) {
        return MAX_TOKENS;
    }

    // Override from BaseLPOracleTest
    function createOracle(uint256 numTokens) public override returns (IBasePool) {
        IStablePool pool = createAndInitPool(numTokens, 100);
        (oracle, feeds) = deployOracle(pool);

        return pool;
    }

    function deployOracle(
        IStablePool pool
    ) internal returns (StableLPOracleMock oracle, AggregatorV3Interface[] memory feeds) {
        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(address(pool));

        feeds = new AggregatorV3Interface[](tokens.length);

        for (uint256 i = 0; i < tokens.length; i++) {
            feeds[i] = AggregatorV3Interface(address(new FeedMock(IERC20Metadata(address(tokens[i])).decimals())));
        }

        oracle = new StableLPOracleMock(IVault(address(vault)), pool, feeds, uptimeFeed, UPTIME_RESYNC_WINDOW, VERSION);
    }

    function createAndInitPool() internal returns (IStablePool) {
        IStablePool pool = createAndInitPool(2, 100);
        return pool;
    }

    function createAndInitPool(uint256 totalTokens, uint256 amplificationParameter) internal returns (IStablePool) {
        return createAndInitPool(totalTokens, amplificationParameter, false);
    }

    function createAndInitPool(
        uint256 totalTokens,
        uint256 amplificationParameter,
        bool with18DecimalTokens
    ) internal returns (IStablePool) {
        address[] memory _tokens = new address[](totalTokens);
        uint256[] memory poolInitAmounts = new uint256[](totalTokens);

        for (uint256 i = 0; i < totalTokens; i++) {
            _tokens[i] = with18DecimalTokens ? address(sortedTokens18[i]) : address(sortedTokens[i]);
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
        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(newPool);
        try router.initialize(newPool, tokens, initAmounts, 0, false, bytes("")) {} catch {
            // If the initialization of the pool failed, probably the Stable Invariant did not converge. So, ignore this test.
            // This condition only happens in fuzz tests, when fuzzying the initial balances of a stable pool.
            vm.assume(false);
        }
        vm.stopPrank();

        return IStablePool(newPool);
    }

    function testDescription() public {
        IStablePool pool = createAndInitPool();
        (StableLPOracleMock oracle, ) = deployOracle(pool);

        assertEq(oracle.description(), "STABLE-TEST/USD", "Description does not match");
    }

    function testComputeMarketPriceBalances__Fuzz(
        uint256 totalTokens,
        uint256 amplificationParameter,
        uint256[MAX_TOKENS] memory poolInitAmountsRaw,
        uint256[MAX_TOKENS] memory pricesRaw
    ) public {
        totalTokens = bound(totalTokens, MIN_TOKENS, MAX_TOKENS);
        amplificationParameter = bound(amplificationParameter, StableMath.MIN_AMP, StableMath.MAX_AMP);

        uint256[] memory prices = new uint256[](totalTokens);
        int256[] memory pricesInt = new int256[](totalTokens);
        IStablePool pool;
        StableLPOracleMock oracle;
        {
            uint256[] memory poolInitAmounts = new uint256[](totalTokens);
            address[] memory _tokens = new address[](totalTokens);

            // Since the ratio between the min price and max price cannot be higher than PRICE_RATIO_LIMIT, we need a
            // way to test different price ranges. `priceBase` will define what will be the minimum possible price, so
            // the prices in the price array will be in the interval [priceBase, priceBase * PRICE_RATIO_LIMIT / 2].
            uint256 priceBase = bound(pricesRaw[0], MIN_PRICE, MAX_PRICE / (PRICE_RATIO_LIMIT / 2));

            for (uint256 i = 0; i < totalTokens; i++) {
                _tokens[i] = address(sortedTokens[i]);
                uint256 tokenDecimals = IERC20Metadata(address(sortedTokens[i])).decimals();
                poolInitAmounts[i] =
                    bound(poolInitAmountsRaw[i], FixedPoint.ONE, 1e9 * FixedPoint.ONE) /
                    (10 ** (18 - tokenDecimals));
                // The prices will be in the interval [priceBase, priceBase * PRICE_RATIO_LIMIT / 2]. It means, we are
                // sure that the ratio between the maximum and minimum prices is less than PRICE_RATIO_LIMIT, and the
                // oracle will not revert.
                prices[i] =
                    bound(pricesRaw[i], priceBase, ((priceBase * PRICE_RATIO_LIMIT) / 2).mulDown(0.99e18)) /
                    (10 ** (18 - tokenDecimals));

                uint256 price = prices[i] * (10 ** (18 - tokenDecimals));
                pricesInt[i] = int256(price);
            }

            pool = createAndInitPool(_tokens, poolInitAmounts, amplificationParameter);
            (oracle, ) = deployOracle(pool);
        }

        uint256 D = _getInvariant(amplificationParameter * StableMath.AMP_PRECISION, address(pool));
        int256[] memory normalizedPrices = oracle.normalizePrices(pricesInt);

        uint256[] memory marketPriceBalancesScaled18 = oracle.computeMarketPriceBalances(D, normalizedPrices);
        _checkPricesAndInvariant(amplificationParameter, marketPriceBalancesScaled18, D, totalTokens, pricesInt);
    }

    function testLatestRoundDataMinPriceTooSmall() public {
        uint256 totalTokens = 2;

        address[] memory _tokens = new address[](totalTokens);
        uint256[] memory poolInitAmounts = new uint256[](totalTokens);
        uint256[] memory prices = new uint256[](totalTokens);
        uint256[] memory updateTimestamps = new uint256[](totalTokens);

        uint256 minUpdateTimestamp = MAX_UINT256;
        {
            // The minimum price will be lower than limit, so the latest round data will revert.
            uint256 priceBase = MIN_PRICE - 1;
            for (uint256 i = 0; i < totalTokens; i++) {
                _tokens[i] = address(sortedTokens[i]);
                uint256 tokenDecimals = IERC20Metadata(address(sortedTokens[i])).decimals();
                poolInitAmounts[i] = 1e18 / (10 ** (18 - tokenDecimals));
                prices[i] = priceBase / (10 ** (18 - tokenDecimals));
                updateTimestamps[i] = block.timestamp;

                if (updateTimestamps[i] < minUpdateTimestamp) {
                    minUpdateTimestamp = updateTimestamps[i];
                }
            }
        }

        createOracle(totalTokens);

        for (uint256 i = 0; i < totalTokens; i++) {
            FeedMock(address(feeds[i])).setLastRoundData(prices[i], updateTimestamps[i]);
        }

        int256[] memory pricesInt = new int256[](totalTokens);
        for (uint256 i = 0; i < totalTokens; i++) {
            uint256 price = prices[i] * oracle.getFeedTokenDecimalScalingFactors()[i];
            pricesInt[i] = int256(price);
        }

        vm.expectRevert(StableLPOracle.MinPriceTooLow.selector);
        oracle.latestRoundData();
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
            uint256 priceBase = bound(pricesRaw[0], MIN_PRICE, MAX_PRICE / (PRICE_RATIO_LIMIT / 2));

            for (uint256 i = 0; i < totalTokens; i++) {
                _tokens[i] = address(sortedTokens[i]);
                uint256 tokenDecimals = IERC20Metadata(address(sortedTokens[i])).decimals();
                poolInitAmounts[i] =
                    bound(poolInitAmountsRaw[i], FixedPoint.ONE, 1e9 * FixedPoint.ONE) /
                    (10 ** (18 - tokenDecimals));
                prices[i] =
                    bound(pricesRaw[i], priceBase, ((priceBase * PRICE_RATIO_LIMIT) / 2).mulDown(0.99e18)) /
                    (10 ** (18 - tokenDecimals));

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
        uint256 expectedTVL = oracle.computeTVLGivenPrices(pricesInt);

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

    function testComputeTVLHighPriceRatio() public {
        uint256 totalTokens = 2;
        uint256 amplificationParameter = 100;

        address[] memory _tokens = new address[](totalTokens);
        uint256[] memory poolInitAmounts = new uint256[](totalTokens);
        int256[] memory prices = new int256[](totalTokens);

        for (uint256 i = 0; i < totalTokens; i++) {
            _tokens[i] = address(sortedTokens[i]);
            uint256 tokenDecimals = IERC20Metadata(address(sortedTokens[i])).decimals();
            poolInitAmounts[i] = 1000e18 / (10 ** (18 - tokenDecimals));
            int256 rawPrice = i == 0 ? int256(1e24) : int256(1e10);
            prices[i] = rawPrice / int256(10 ** (18 - tokenDecimals));
        }

        IStablePool pool = createAndInitPool(_tokens, poolInitAmounts, amplificationParameter);
        (StableLPOracleMock oracle, ) = deployOracle(pool);

        int256[] memory pricesInt = new int256[](totalTokens);
        for (uint256 i = 0; i < totalTokens; i++) {
            uint256 price = uint256(prices[i]) * oracle.getFeedTokenDecimalScalingFactors()[i];
            pricesInt[i] = int256(price);
        }

        vm.expectRevert(StableLPOracle.PriceRatioTooHigh.selector);
        oracle.computeTVLGivenPrices(pricesInt);
    }

    function testComputeKNotConverging() public {
        uint256 amplificationParameter = 1;

        IStablePool pool;
        StableLPOracleMock oracle;

        uint256[] memory poolInitAmounts = [uint256(563_360_193e18), uint256(10_000_000e18)].toMemoryArray();
        address[] memory _tokens = [address(sortedTokens[0]), address(sortedTokens[1])].toMemoryArray();

        pool = createAndInitPool(_tokens, poolInitAmounts, amplificationParameter);
        (oracle, ) = deployOracle(pool);

        // Prices found empirically, by running a forge fuzz test that had K convergence error.
        int256[] memory pricesInt = new int256[](2);
        pricesInt[0] = int256(55_529_888e18);
        pricesInt[1] = int256(1e9);

        vm.expectRevert(StableLPOracle.KDidNotConverge.selector);
        oracle.computeK(pricesInt);
    }

    function _checkPricesAndInvariant(
        uint256 amplificationParameter,
        uint256[] memory balancesForPricesScaled18,
        uint256 D,
        uint256 totalTokens,
        int256[] memory prices
    ) private view {
        uint256 newD;
        try
            StableLPOracleTest(address(this)).computeInvariant(
                amplificationParameter * StableMath.AMP_PRECISION,
                balancesForPricesScaled18
            )
        returns (uint256 invariant) {
            newD = invariant;
        } catch {
            vm.assume(false);
        }

        assertApproxEqRel(D, newD, 1e12, "Invariant does not match");

        uint256 amountInScaled18 = balancesForPricesScaled18[0].mulDown(0.00001e16); // 0.00001% of first token balance.
        for (uint256 i = 1; i < totalTokens; i++) {
            // `amountOutScaled18` is how much of token[i] you get for a tiny (infinitesimal) fraction of token[0].
            // Therefore, `amountInScaled18 / amountOutScaled18` represents the spot price of token 0 wrt token i.
            // Multiplying `spotPrice` by `price[0]` should result in `price[i]`.
            uint256 amountOutScaled18 = StableMath.computeOutGivenExactIn(
                amplificationParameter * StableMath.AMP_PRECISION,
                balancesForPricesScaled18,
                0,
                i,
                amountInScaled18,
                newD
            );
            assertApproxEqRel(
                uint256(prices[0]).mulDown(amountInScaled18).divDown(amountOutScaled18),
                uint256(prices[i]),
                0.1e16, // 0.1% error
                "Price does not match"
            );
        }
    }

    function _getInvariant(uint256 amplificationParameter, address pool) private view returns (uint256 invariant) {
        (, , , uint256[] memory liveBalancesScaled18) = vault.getPoolTokenInfo(pool);
        invariant = StableMath.computeInvariant(amplificationParameter, liveBalancesScaled18);
    }

    function computeInvariant(
        uint256 amplificationParameter,
        uint256[] memory balances
    ) external pure returns (uint256 invariant) {
        return StableMath.computeInvariant(amplificationParameter, balances);
    }
}
