// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import { HyperSpotPricePrecompile } from "./utils/HyperSpotPricePrecompile.sol";
import { HyperTokenInfoPrecompile } from "./utils/HyperTokenInfoPrecompile.sol";

contract HyperEVMRateProvider {
    uint256 private immutable _spotPriceDivisor;
    uint32 private immutable _pairIndex;
    uint32 private immutable _tokenIndex;

    constructor(uint32 tokenIndex, uint32 pairIndex) {
        uint8 szDecimals = HyperTokenInfoPrecompile.szDecimals(tokenIndex);
        _spotPriceDivisor = 10 ** (8 - szDecimals);

        _pairIndex = pairIndex;
        _tokenIndex = tokenIndex;
    }

    function getSpotPriceDivisor() external view returns (uint256) {
        return _spotPriceDivisor;
    }

    function getTokenIndex() external view returns (uint32) {
        return _tokenIndex;
    }

    function getPairIndex() external view returns (uint32) {
        return _pairIndex;
    }

    function getRate() external view returns (uint256) {
        uint256 spotPrice = HyperSpotPricePrecompile.spotPrice(_pairIndex);
        return (spotPrice * 1e18) / _spotPriceDivisor;
    }
}
