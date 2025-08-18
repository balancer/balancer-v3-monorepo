// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

interface IHyperEVMRateProvider {
    /**
     * @notice The index of the token on Hyperliquid API.
     * @return tokenIndex The index of the token on Hyperliquid API
     */
    function getTokenIndex() external view returns (uint32);

    /**
     * @notice The index of the pair of the spot price on Hyperliquid API.
     * @return pairIndex The index of the pair on Hyperliquid API
     */
    function getPairIndex() external view returns (uint32);

    /**
     * @notice The spot price divisor.
     * @dev The spot price divisor is computed as 10 ** (8 - szDecimals), where szDecimals is the number of decimals of the token.
     * szDecimals is fetched using the TOKEN INFO precompile of Hypercore.
     * @return spotPriceDivisor The spot price divisor
     */
    function getSpotPriceDivisor() external view returns (uint256 spotPriceDivisor);
}
