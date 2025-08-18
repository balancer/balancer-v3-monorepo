// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

library HyperTokenInfoPrecompile {
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
