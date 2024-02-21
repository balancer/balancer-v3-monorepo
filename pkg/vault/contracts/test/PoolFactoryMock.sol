// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { FactoryWidePauseWindow } from "../factories/FactoryWidePauseWindow.sol";
import { PoolConfigBits, PoolConfigLib } from "../lib/PoolConfigLib.sol";

contract PoolFactoryMock is FactoryWidePauseWindow {
    uint256 private constant DEFAULT_SWAP_FEE = 0;

    IVault private immutable _vault;

    constructor(IVault vault, uint256 pauseWindowDuration) FactoryWidePauseWindow(pauseWindowDuration) {
        _vault = vault;
    }

    function registerTestPool(address pool, TokenConfig[] memory tokenConfig) external {
        _vault.registerPool(
            pool,
            tokenConfig,
            DEFAULT_SWAP_FEE,
            getNewPoolPauseWindowEndTime(),
            address(0),
            PoolConfigBits.wrap(0).toPoolConfig().hooks,
            PoolConfigBits.wrap(bytes32(type(uint256).max)).toPoolConfig().liquidityManagement
        );
    }

    function registerGeneralTestPool(
        address pool,
        TokenConfig[] memory tokenConfig,
        uint256 swapFee,
        uint256 pauseWindowDuration,
        address pauseManager
    ) external {
        _vault.registerPool(
            pool,
            tokenConfig,
            swapFee,
            block.timestamp + pauseWindowDuration,
            pauseManager,
            PoolConfigBits.wrap(0).toPoolConfig().hooks,
            PoolConfigBits.wrap(bytes32(type(uint256).max)).toPoolConfig().liquidityManagement
        );
    }

    function registerPool(
        address pool,
        TokenConfig[] memory tokenConfig,
        address pauseManager,
        PoolHooks calldata poolHooks,
        LiquidityManagement calldata liquidityManagement
    ) external {
        _vault.registerPool(
            pool,
            tokenConfig,
            DEFAULT_SWAP_FEE,
            getNewPoolPauseWindowEndTime(),
            pauseManager,
            poolHooks,
            liquidityManagement
        );
    }

    function registerPoolWithSwapFee(
        address pool,
        TokenConfig[] memory tokenConfig,
        uint256 swapFeePercentage,
        address pauseManager,
        PoolHooks calldata poolHooks,
        LiquidityManagement calldata liquidityManagement
    ) external {
        _vault.registerPool(
            pool,
            tokenConfig,
            swapFeePercentage,
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
        PoolHooks calldata poolHooks,
        LiquidityManagement calldata liquidityManagement,
        uint256 timestamp
    ) external {
        _vault.registerPool(
            pool,
            tokenConfig,
            DEFAULT_SWAP_FEE,
            timestamp,
            pauseManager,
            poolHooks,
            liquidityManagement
        );
    }
}
