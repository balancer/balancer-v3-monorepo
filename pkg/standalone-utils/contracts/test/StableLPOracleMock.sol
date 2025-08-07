// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IStablePool } from "@balancer-labs/v3-interfaces/contracts/pool-stable/IStablePool.sol";

import { TokenInfo, Rounding } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { StableLPOracle } from "../StableLPOracle.sol";

contract StableLPOracleMock is StableLPOracle {
    constructor(
        IVault vault_,
        IStablePool pool_,
        AggregatorV3Interface[] memory feeds,
        uint256 version_
    ) StableLPOracle(vault_, pool_, feeds, version_) {
        // solhint-disable-previous-line no-empty-blocks
    }

    function computeFeedTokenDecimalScalingFactor(AggregatorV3Interface feed) public view returns (uint256) {
        return _computeFeedTokenDecimalScalingFactor(feed);
    }

    function computeMarketPriceBalances(
        uint256 invariant,
        int256[] memory prices
    ) public view returns (uint256[] memory) {
        return _computeMarketPriceBalances(invariant, prices);
    }

    function calculateRawTVL(int256[] memory prices) public view returns (uint256 tvl) {
        (, TokenInfo[] memory tokenInfo, , uint256[] memory lastBalancesLiveScaled18) = _vault.getPoolTokenInfo(
            address(pool)
        );

        uint256[] memory lastBalancesLiveWithoutRate = new uint256[](lastBalancesLiveScaled18.length);
        for (uint256 i = 0; i < lastBalancesLiveScaled18.length; i++) {
            lastBalancesLiveWithoutRate[i] = (lastBalancesLiveScaled18[i] * 1e18) / tokenInfo[i].rateProvider.getRate();
            console2.log("lastBalancesLiveWithoutRate[%d]: %d", i, lastBalancesLiveWithoutRate[i]);
            console2.log("lastBalancesLiveScaled18[%d]:    %d", i, lastBalancesLiveScaled18[i]);
            console2.log("rate[%d]:                        %d", i, tokenInfo[i].rateProvider.getRate());
        }

        // The TVL of the stable pool is computed by calculating the balances for the stable pool that would represent
        // the given price vector. To compute these balances, we need only the amplification parameter of the pool,
        // the invariant and the price vector.

        uint256 invariant = pool.computeInvariant(lastBalancesLiveWithoutRate, Rounding.ROUND_DOWN);

        uint256[] memory marketPriceBalancesScaled18 = _computeMarketPriceBalances(invariant, prices);

        for (uint256 i = 0; i < _totalTokens; i++) {
            tvl += (uint256(prices[i]) * marketPriceBalancesScaled18[i]) / 1e18;
        }

        return tvl;
    }

    function calculateScaled18TVL(int256[] memory prices) public view returns (uint256 tvl) {
        (, TokenInfo[] memory tokenInfo, , uint256[] memory lastBalancesLiveScaled18) = _vault.getPoolTokenInfo(
            address(pool)
        );

        // The TVL of the stable pool is computed by calculating the balances for the stable pool that would represent
        // the given price vector. To compute these balances, we need only the amplification parameter of the pool,
        // the invariant and the price vector.

        uint256 invariant = pool.computeInvariant(lastBalancesLiveScaled18, Rounding.ROUND_DOWN);

        int256[] memory pricesWithoutRate = new int256[](prices.length);
        for (uint256 i = 0; i < pricesWithoutRate.length; i++) {
            pricesWithoutRate[i] = (prices[i] * 1e18) / int256(tokenInfo[i].rateProvider.getRate());
        }

        uint256[] memory marketPriceBalancesScaled18 = _computeMarketPriceBalances(invariant, pricesWithoutRate);

        for (uint256 i = 0; i < _totalTokens; i++) {
            tvl += (uint256(pricesWithoutRate[i]) * marketPriceBalancesScaled18[i]) / 1e18;
        }

        return tvl;
    }
}
