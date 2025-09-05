// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

import { IStablePool } from "@balancer-labs/v3-interfaces/contracts/pool-stable/IStablePool.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { StableLPOracle } from "../StableLPOracle.sol";

contract StableLPOracleMock is StableLPOracle {
    constructor(
        IVault vault_,
        IStablePool pool_,
        AggregatorV3Interface[] memory feeds,
        AggregatorV3Interface sequencerUptimeFeed,
        uint256 uptimeResyncWindow,
        uint256 version_
    ) StableLPOracle(vault_, pool_, feeds, sequencerUptimeFeed, uptimeResyncWindow, version_) {
        // solhint-disable-previous-line no-empty-blocks
    }

    function computeFeedTokenDecimalScalingFactor(AggregatorV3Interface feed) public view returns (uint256) {
        return _computeFeedTokenDecimalScalingFactor(feed);
    }

    function computeMarketPriceBalances(
        uint256 invariant,
        int256[] memory normalizedPrices
    ) public view returns (uint256[] memory) {
        return _computeMarketPriceBalances(invariant, normalizedPrices);
    }

    function computeK(int256[] memory prices) public view returns (int256) {
        (int256 a, int256 b) = _computeAAndBForPool(IStablePool(address(pool)));
        return _computeK(a, b, prices);
    }

    function normalizePrices(int256[] memory prices) public view returns (int256[] memory normalizedPrices) {
        int256 minPrice = prices[0];
        uint256 minPriceIndex = 0;
        for (uint256 i = 1; i < _totalTokens; i++) {
            if (prices[i] < minPrice) {
                minPrice = prices[i];
                minPriceIndex = i;
            }
        }

        normalizedPrices = new int256[](_totalTokens);
        for (uint256 i = 0; i < _totalTokens; i++) {
            normalizedPrices[i] = i == minPriceIndex ? int256(FixedPoint.ONE) : _divDownInt(prices[i], minPrice);
        }

        return normalizedPrices;
    }
}
