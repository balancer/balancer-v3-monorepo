// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { TokenConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import "../helpers/InputHelpers.sol";

contract InputHelpersMock {
    function sortTokens(IERC20[] memory tokens) external pure returns (IERC20[] memory) {
        return InputHelpers.sortTokens(tokens);
    }

    function ensureSortedTokens(IERC20[] memory tokens) external pure {
        InputHelpers.ensureSortedTokens(tokens);
    }

    function sortTokenConfig(TokenConfig[] memory tokenConfig) public pure returns (TokenConfig[] memory) {
        for (uint256 i = 0; i < tokenConfig.length - 1; ++i) {
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
