// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

library HyperSpotPricePrecompile {
    address public constant SPOT_PRICE_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000808; // spotPx
    error SpotPricePrecompileFailed();

    function spotPrice(uint32 pairIndex) internal view returns (uint256) {
        (bool success, bytes memory spotPriceBytes) = SPOT_PRICE_PRECOMPILE_ADDRESS.staticcall(abi.encode(pairIndex));
        if (success == false) {
            revert SpotPricePrecompileFailed();
        }
        return abi.decode(spotPriceBytes, (uint256));
    }
}
