// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

interface IHyperEVMRateProvider {
    /**
     * @notice The index of the token on the Hyperliquid public API.
     * @return tokenIndex The index of the token on the Hyperliquid public API
     */
    function getTokenIndex() external view returns (uint32);

    /**
     * @notice The index of the pair to fetch the spot price, according to the Hyperliquid public API.
     * @dev Hypercore has an index that identifies a pair of tokens to fetch the spot price.
     * @return pairIndex The index of the pair to fetch the spot price, according to the Hyperliquid public API
     */
    function getPairIndex() external view returns (uint32);

    /**
     * @notice The spot price multiplier.
     * @dev Hypercore returns the spot price with a different number of decimals for each token. So, to make this rate
     * provider compatible with the vault, we need to scale the spot price to 18 decimals using this multiplier.
     * @return spotPriceMultiplier The spot price multiplier
     */
    function getSpotPriceMultiplier() external view returns (uint256 spotPriceMultiplier);
}
