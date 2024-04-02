// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { PoolConfigBits, PoolConfigLib } from "../lib/PoolConfigLib.sol";

import { FactoryWidePauseWindow } from "../factories/FactoryWidePauseWindow.sol";
import { TokenConfigLib } from "../lib/TokenConfigLib.sol";

contract PoolFactoryMock is FactoryWidePauseWindow {
    IVault private immutable _vault;
    bytes32 private constant _ALL_BITS_SET = bytes32(type(uint256).max);

    constructor(IVault vault, uint256 pauseWindowDuration) FactoryWidePauseWindow(pauseWindowDuration) {
        _vault = vault;
    }

    // Used for testing pool registration, which is ordinarily done in the pool factory.
    // The Mock pool has an argument for whether or not to register on deployment. To call register pool
    // separately, deploy it with the registration flag false, then call this function.
    function manualRegisterPool(address pool, IERC20[] memory tokens) external {
        registerPool(
            pool,
            TokenConfigLib.buildTokenConfig(tokens),
            address(0),
            PoolConfigBits.wrap(0).toPoolConfig().hooks,
            PoolConfigBits.wrap(_ALL_BITS_SET).toPoolConfig().liquidityManagement
        );
    }

    function manualRegisterPoolPassThruTokens(address pool, IERC20[] memory tokens) external {
        TokenConfig[] memory tokenConfig = new TokenConfig[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            tokenConfig[i].token = tokens[i];
        }

        registerPool(
            pool,
            tokenConfig,
            address(0),
            PoolConfigBits.wrap(0).toPoolConfig().hooks,
            PoolConfigBits.wrap(_ALL_BITS_SET).toPoolConfig().liquidityManagement
        );
    }

    function manualRegisterPoolAtTimestamp(
        address pool,
        IERC20[] memory tokens,
        uint256 timestamp,
        address pauseManager
    ) external {
        registerPoolAtTimestamp(
            pool,
            TokenConfigLib.buildTokenConfig(tokens),
            pauseManager,
            PoolConfigBits.wrap(0).toPoolConfig().hooks,
            PoolConfigBits.wrap(_ALL_BITS_SET).toPoolConfig().liquidityManagement,
            timestamp
        );
    }

    function registerPool(
        address pool,
        TokenConfig[] memory tokenConfig,
        address pauseManager,
        PoolHooks memory poolHooks,
        LiquidityManagement memory liquidityManagement
    ) public {
        _vault.registerPool(
            pool,
            tokenConfig,
            getNewPoolPauseWindowEndTime(),
            pauseManager,
            poolHooks,
            liquidityManagement
        );
    }

    // For tests; otherwise can't get the exact event arguments.
    function registerPoolAtTimestamp(
        address pool,
        TokenConfig[] memory tokenConfig,
        address pauseManager,
        PoolHooks memory poolHooks,
        LiquidityManagement memory liquidityManagement,
        uint256 timestamp
    ) public {
        _vault.registerPool(pool, tokenConfig, timestamp, pauseManager, poolHooks, liquidityManagement);
    }
}
