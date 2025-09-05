// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import {
    IHyperEVMRateProvider
} from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IHyperEVMRateProvider.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";

import { HyperSpotPricePrecompile } from "./utils/HyperSpotPricePrecompile.sol";
import { HyperTokenInfoPrecompile } from "./utils/HyperTokenInfoPrecompile.sol";

/**
 * @notice A rate provider for the HyperEVM.
 * @dev HyperEVM has precompiles that allow to fetch the spot price of a token (in terms of USD or other tokens).
 * This contract uses the spot price and the token info precompiles to return the rate of a token on-chain,
 * scaled with 18 decimals (compatible with the Vault).
 */
contract HyperEVMRateProvider is IRateProvider, IHyperEVMRateProvider {
    uint256 private immutable _spotPriceMultiplier;
    uint32 private immutable _pairIndex;
    uint32 private immutable _tokenIndex;

    constructor(uint32 tokenIndex, uint32 pairIndex) {
        uint8 szDecimals = HyperTokenInfoPrecompile.szDecimals(tokenIndex);
        // The spot price is returned with a different number of decimals for each token. So, to make this rate
        // provider compatible with the vault, we need to scale the spot price to 18 decimals using this multiplier.
        // According to hyperliquid's documentation
        // (https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/hyperevm/interacting-with-hypercore),
        // szDecimals has a minimum of 0 and a maximum of 8, so the multiplier is always between 1e10 and 1e18.
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
