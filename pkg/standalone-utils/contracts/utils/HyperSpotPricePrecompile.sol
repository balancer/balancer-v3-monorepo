// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

/**
 * @notice Library to interact with the Hyperliquid spot price precompile.
 * @dev The precompile is a special type of code, executed in the Hypercore's node. For more information, see
 * https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/hyperevm/interacting-with-hypercore .
 */
library HyperSpotPricePrecompile {
    address public constant SPOT_PRICE_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000808;

    /// @notice The precompile had an error while fetching the spot price.
    error SpotPricePrecompileFailed();

    /// @notice The spot price is zero.
    error SpotPriceIsZero();

    function spotPrice(uint32 pairIndex) internal view returns (uint256) {
        (bool success, bytes memory spotPriceBytes) = SPOT_PRICE_PRECOMPILE_ADDRESS.staticcall(abi.encode(pairIndex));
        if (success == false) {
            revert SpotPricePrecompileFailed();
        }
        uint256 price = abi.decode(spotPriceBytes, (uint256));
        if (price == 0) {
            revert SpotPriceIsZero();
        }
        return price;
    }
}
