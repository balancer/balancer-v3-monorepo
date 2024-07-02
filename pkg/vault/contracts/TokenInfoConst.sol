// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    TokenConfig,
    TokenInfo,
    TokenType,
    IRateProvider
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

contract TokenInfoConst {
    error InvalidTokenInfoLength(uint length);

    uint256 immutable size;
    IERC20 immutable tokenOne;
    TokenType immutable tokenTypeOne;
    IRateProvider immutable rateProviderOne;
    bool immutable paysYieldFeesOne;

    IERC20 immutable tokenTwo;
    TokenType immutable tokenTypeTwo;
    IRateProvider immutable rateProviderTwo;
    bool immutable paysYieldFeesTwo;

    IERC20 immutable tokenThree;
    TokenType immutable tokenTypeThree;
    IRateProvider immutable rateProviderThree;
    bool immutable paysYieldFeesThree;

    IERC20 immutable tokenFour;
    TokenType immutable tokenTypeFour;
    IRateProvider immutable rateProviderFour;
    bool immutable paysYieldFeesFour;

    constructor(TokenConfig[] memory _tokenConfig) {
        uint length = _tokenConfig.length;
        size = length;
        if (length > 4) {
            revert InvalidTokenInfoLength(length);
        }

        if (length >= 1) {
            tokenOne = _tokenConfig[0].token;
            tokenTypeOne = _tokenConfig[0].tokenType;
            rateProviderOne = _tokenConfig[0].rateProvider;
            paysYieldFeesOne = _tokenConfig[0].paysYieldFees;
        }

        if (length >= 2) {
            tokenTwo = _tokenConfig[1].token;
            tokenTypeTwo = _tokenConfig[1].tokenType;
            rateProviderTwo = _tokenConfig[1].rateProvider;
            paysYieldFeesTwo = _tokenConfig[1].paysYieldFees;
        }

        if (length >= 3) {
            tokenThree = _tokenConfig[2].token;
            tokenTypeThree = _tokenConfig[2].tokenType;
            rateProviderThree = _tokenConfig[2].rateProvider;
            paysYieldFeesThree = _tokenConfig[2].paysYieldFees;
        }

        if (length == 4) {
            tokenFour = _tokenConfig[3].token;
            tokenTypeFour = _tokenConfig[3].tokenType;
            rateProviderFour = _tokenConfig[3].rateProvider;
            paysYieldFeesFour = _tokenConfig[3].paysYieldFees;
        }
    }

    function getTokenInfo() public view returns (IERC20[] memory tokens, TokenInfo[] memory tokenInfo) {
        tokenInfo = new TokenInfo[](size);
        tokens = new IERC20[](size);

        if (size >= 1) {
            tokenInfo[0] = TokenInfo(tokenTypeOne, rateProviderOne, paysYieldFeesOne);
            tokens[0] = tokenOne;
        }

        if (size >= 2) {
            tokenInfo[1] = TokenInfo(tokenTypeTwo, rateProviderTwo, paysYieldFeesTwo);
            tokens[1] = tokenTwo;
        }

        if (size >= 3) {
            tokenInfo[2] = TokenInfo(tokenTypeThree, rateProviderThree, paysYieldFeesThree);
            tokens[2] = tokenThree;
        }

        if (size == 4) {
            tokenInfo[3] = TokenInfo(tokenTypeFour, rateProviderFour, paysYieldFeesFour);
            tokens[3] = tokenFour;
        }
    }
}
