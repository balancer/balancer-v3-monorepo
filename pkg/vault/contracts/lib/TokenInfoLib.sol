// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { WordCodec } from "@balancer-labs/v3-solidity-utils/contracts/helpers/WordCodec.sol";

type TokenInfoContract is address;

library TokenInfoLib {
    using WordCodec for bytes32;

    uint8 public constant UINT8_BITLENGTH = 8;
    uint8 public constant ADDRESS_BITLENGTH = 160;
    uint8 public constant DEPLOY_CODE_BYTE_SIZE = 12;

    // Bit offsets for main pool config settings
    uint8 public constant TOKEN_TYPE_OFFSET = 0;
    uint8 public constant RATE_PROVIDER_OFFSET = TOKEN_TYPE_OFFSET + UINT8_BITLENGTH;
    uint8 public constant PAYS_YIELD_FEES_OFFSET = RATE_PROVIDER_OFFSET + ADDRESS_BITLENGTH;

    function set(TokenConfig[] memory tokenInfo) internal returns (TokenInfoContract tokenInfoContract) {
        uint256 length = tokenInfo.length;
        uint8 totalBytes = uint8(length * 2 * 32);
        uint256 deployScriptSize = DEPLOY_CODE_BYTE_SIZE + totalBytes;

        bytes memory result = new bytes(deployScriptSize);
        result[0] = 0x60;
        result[1] = bytes1(totalBytes);
        result[2] = 0x60;
        result[3] = 0x0c;
        result[4] = 0x60;
        result[5] = 0x00;
        result[6] = 0x39;
        result[7] = 0x60;
        result[8] = bytes1(totalBytes);
        result[9] = 0x60;
        result[10] = 0x00;
        result[11] = 0xf3;

        for (uint256 i = 0; i < length; i++) {
            bytes32 tokenAddress;
            tokenAddress = tokenAddress.insertAddress(address(tokenInfo[i].token), 0);

            bytes32 tokenInfoBits;
            tokenInfoBits = tokenInfoBits.insertUint(uint8(tokenInfo[i].tokenType), TOKEN_TYPE_OFFSET, UINT8_BITLENGTH);
            tokenInfoBits = tokenInfoBits.insertAddress(address(tokenInfo[i].rateProvider), RATE_PROVIDER_OFFSET);
            tokenInfoBits = tokenInfoBits.insertBool(tokenInfo[i].paysYieldFees, PAYS_YIELD_FEES_OFFSET);
            uint one = 12 + 32 + i * 64;
            uint two = 12 + 64 + i * 64;

            assembly {
                mstore(add(result, one), tokenAddress)
                mstore(add(result, two), tokenInfoBits)
            }
        }
        assembly {
            tokenInfoContract := create(0, add(result, 32), deployScriptSize)
        }
    }

    function getTokensAndTokenInfo(
        TokenInfoContract tokenInfoContract
    ) internal view returns (IERC20[] memory tokens, TokenInfo[] memory tokensInfo) {
        bytes memory data = TokenInfoContract.unwrap(tokenInfoContract).code;

        uint length = data.length / 64;

        tokens = new IERC20[](length);
        tokensInfo = new TokenInfo[](length);

        for (uint256 i = 0; i < length; i++) {
            bytes32 tokenAddress;
            bytes32 tokenInfoBits;
            uint one = 32 + i * 64;
            uint two = 64 + i * 64;
            assembly {
                tokenAddress := mload(add(data, one))
                tokenInfoBits := mload(add(data, two))
            }

            tokens[i] = IERC20(tokenAddress.decodeAddress(0));
            tokensInfo[i].tokenType = TokenType(tokenInfoBits.decodeUint(TOKEN_TYPE_OFFSET, UINT8_BITLENGTH));
            tokensInfo[i].rateProvider = IRateProvider(tokenInfoBits.decodeAddress(RATE_PROVIDER_OFFSET));
            tokensInfo[i].paysYieldFees = tokenInfoBits.decodeBool(PAYS_YIELD_FEES_OFFSET);
        }
    }
}
