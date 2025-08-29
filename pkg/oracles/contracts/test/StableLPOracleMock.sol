// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

import { IStablePool } from "@balancer-labs/v3-interfaces/contracts/pool-stable/IStablePool.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

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

    function computeK(int256[] memory prices) public view returns (int256) {
        (int256 a, int256 b) = _computeAAndBForPool(IStablePool(address(pool)));
        return _computeK(a, b, prices);
    }
}
