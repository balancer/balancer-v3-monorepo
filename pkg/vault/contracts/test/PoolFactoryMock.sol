// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {
    IVault,
    TokenConfig,
    TokenType,
    PoolCallbacks,
    LiquidityManagement
} from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";

import { FactoryWidePauseWindow } from "../factories/FactoryWidePauseWindow.sol";

contract PoolFactoryMock is FactoryWidePauseWindow {
    IVault private immutable _vault;

    constructor(IVault vault, uint256 pauseWindowDuration) FactoryWidePauseWindow(pauseWindowDuration) {
        _vault = vault;
    }

    function registerPool(
        address pool,
        IERC20[] memory tokens,
        IRateProvider[] memory rateProviders,
        address pauseManager,
        PoolCallbacks calldata poolCallbacks,
        LiquidityManagement calldata liquidityManagement
    ) external {
        _vault.registerPool(
            pool,
            _buildTokenConfig(tokens, rateProviders),
            getNewPoolPauseWindowEndTime(),
            pauseManager,
            poolCallbacks,
            liquidityManagement
        );
    }

    // For tests; otherwise can't get the exact event arguments.
    function registerPoolAtTimestamp(
        address pool,
        IERC20[] memory tokens,
        IRateProvider[] memory rateProviders,
        address pauseManager,
        PoolCallbacks calldata poolCallbacks,
        LiquidityManagement calldata liquidityManagement,
        uint256 timestamp
    ) external {
        _vault.registerPool(
            pool,
            _buildTokenConfig(tokens, rateProviders),
            timestamp,
            pauseManager,
            poolCallbacks,
            liquidityManagement
        );
    }

    function _buildTokenConfig(
        IERC20[] memory tokens,
        IRateProvider[] memory rateProviders
    ) private pure returns (TokenConfig[] memory tokenData) {
        tokenData = new TokenConfig[](tokens.length);
        // Assume standard tokens
        for (uint256 i = 0; i < tokens.length; i++) {
            tokenData[i].token = tokens[i];
            tokenData[i].rateProvider = rateProviders[i];
            tokenData[i].tokenType = rateProviders[i] == IRateProvider(address(0))
                ? TokenType.STANDARD
                : TokenType.WITH_RATE;
        }
    }
}
