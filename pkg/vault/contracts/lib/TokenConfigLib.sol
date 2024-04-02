// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";
import { TokenType, TokenConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

library TokenConfigLib {
    function buildTokenConfig(IERC20[] memory tokens) internal pure returns (TokenConfig[] memory tokenConfig) {
        tokenConfig = new TokenConfig[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            tokenConfig[i].token = tokens[i];
        }

        tokenConfig = sortTokenConfig(tokenConfig);
    }

    function buildTokenConfig(
        IERC20[] memory tokens,
        IRateProvider[] memory rateProviders
    ) internal pure returns (TokenConfig[] memory tokenConfig) {
        tokenConfig = new TokenConfig[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            tokenConfig[i].token = tokens[i];
            tokenConfig[i].rateProvider = rateProviders[i];
            tokenConfig[i].tokenType = rateProviders[i] == IRateProvider(address(0))
                ? TokenType.STANDARD
                : TokenType.WITH_RATE;
        }

        tokenConfig = sortTokenConfig(tokenConfig);
    }

    function buildTokenConfig(
        IERC20[] memory tokens,
        IRateProvider[] memory rateProviders,
        bool[] memory yieldFeeFlags
    ) internal pure returns (TokenConfig[] memory tokenConfig) {
        tokenConfig = new TokenConfig[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            tokenConfig[i].token = tokens[i];
            tokenConfig[i].rateProvider = rateProviders[i];
            tokenConfig[i].tokenType = rateProviders[i] == IRateProvider(address(0))
                ? TokenType.STANDARD
                : TokenType.WITH_RATE;
            tokenConfig[i].paysYieldFees = yieldFeeFlags[i];
        }

        tokenConfig = sortTokenConfig(tokenConfig);
    }

    function buildTokenConfig(
        IERC20[] memory tokens,
        TokenType[] memory tokenTypes,
        IRateProvider[] memory rateProviders,
        bool[] memory yieldFeeFlags
    ) internal pure returns (TokenConfig[] memory tokenConfig) {
        tokenConfig = new TokenConfig[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            tokenConfig[i].token = tokens[i];
            tokenConfig[i].tokenType = tokenTypes[i];
            tokenConfig[i].rateProvider = rateProviders[i];
            tokenConfig[i].paysYieldFees = yieldFeeFlags[i];
        }

        tokenConfig = sortTokenConfig(tokenConfig);
    }

    function sortTokenConfig(TokenConfig[] memory tokenConfig) internal pure returns (TokenConfig[] memory) {
        for (uint256 i = 0; i < tokenConfig.length - 1; i++) {
            for (uint256 j = 0; j < tokenConfig.length - i - 1; j++) {
                if (tokenConfig[j].token > tokenConfig[j + 1].token) {
                    // Swap if they're out of order.
                    (tokenConfig[j], tokenConfig[j + 1]) = (tokenConfig[j + 1], tokenConfig[j]);
                }
            }
        }

        return tokenConfig;
    }
}
