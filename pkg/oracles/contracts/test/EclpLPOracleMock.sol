// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

import { IGyroECLPPool } from "@balancer-labs/v3-interfaces/contracts/pool-gyro/IGyroECLPPool.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { EclpLPOracle } from "../EclpLPOracle.sol";

contract EclpLPOracleMock is EclpLPOracle {
    constructor(
        IVault vault_,
        IGyroECLPPool pool_,
        AggregatorV3Interface[] memory feeds,
        uint256 version_
    ) EclpLPOracle(vault_, pool_, feeds, AggregatorV3Interface(address(0)), 0, version_) {
        // solhint-disable-previous-line no-empty-blocks
    }

    function computeFeedTokenDecimalScalingFactor(AggregatorV3Interface feed) public view returns (uint256) {
        return _computeFeedTokenDecimalScalingFactor(feed);
    }

    function computeTVL(int256[] memory prices) public view returns (uint256) {
        return _computeTVL(prices);
    }
}
