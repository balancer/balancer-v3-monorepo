// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

/**
 * @notice Library to interact with the Hyperliquid token info precompile.
 * @dev The precompile is a special type of code, executed in the Hypercore's node. For more information, see
 * https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/hyperevm/interacting-with-hypercore .
 */
library HyperTokenInfoPrecompile {
    // The following structure is defined by the token info precompile.
    struct HyperTokenInfo {
        string name;
        uint64[] spots;
        uint64 deployerTradingFeeShare;
        address deployer;
        address evmContract;
        uint8 szDecimals;
        uint8 weiDecimals;
        int8 evmExtraWeiDecimals;
    }

    address public constant TOKEN_INFO_PRECOMPILE_ADDRESS = 0x000000000000000000000000000000000000080C;

    /// @notice The precompile had an error while fetching the token info.
    error TokenInfoPrecompileFailed();

    function szDecimals(uint32 tokenIndex) internal view returns (uint8) {
        (bool success, bytes memory out) = TOKEN_INFO_PRECOMPILE_ADDRESS.staticcall(abi.encode(tokenIndex));
        if (success == false) {
            revert TokenInfoPrecompileFailed();
        }
        HyperTokenInfo memory tokenInfo = abi.decode(out, (HyperTokenInfo));
        return tokenInfo.szDecimals;
    }
}
