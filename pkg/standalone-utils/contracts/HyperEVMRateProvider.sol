// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import {
    IHyperEVMRateProvider
} from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IHyperEVMRateProvider.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";

import { HyperSpotPricePrecompile } from "./utils/HyperSpotPricePrecompile.sol";
import { HyperTokenInfoPrecompile } from "./utils/HyperTokenInfoPrecompile.sol";

contract HyperEVMRateProvider is IRateProvider, IHyperEVMRateProvider {
    uint256 private immutable _spotPriceMultiplier;
    uint32 private immutable _pairIndex;
    uint32 private immutable _tokenIndex;

    constructor(uint32 tokenIndex, uint32 pairIndex) {
        uint8 szDecimals = HyperTokenInfoPrecompile.szDecimals(tokenIndex);
        _spotPriceMultiplier = 1e18 / (10 ** (8 - szDecimals));

        _pairIndex = pairIndex;
        _tokenIndex = tokenIndex;
    }

    /// @inheritdoc IHyperEVMRateProvider
    function getSpotPriceMultiplier() external view returns (uint256) {
        return _spotPriceMultiplier;
    }

    /// @inheritdoc IHyperEVMRateProvider
    function getTokenIndex() external view returns (uint32) {
        return _tokenIndex;
    }

    /// @inheritdoc IHyperEVMRateProvider
    function getPairIndex() external view returns (uint32) {
        return _pairIndex;
    }

    /// @inheritdoc IRateProvider
    function getRate() external view returns (uint256) {
        uint256 spotPrice = HyperSpotPricePrecompile.spotPrice(_pairIndex);
        return spotPrice * _spotPriceMultiplier;
    }
}
