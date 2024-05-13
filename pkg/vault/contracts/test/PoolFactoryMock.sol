// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { FactoryWidePauseWindow } from "../factories/FactoryWidePauseWindow.sol";
import { PoolConfigBits, PoolConfigLib } from "../lib/PoolConfigLib.sol";

contract PoolFactoryMock is FactoryWidePauseWindow {
    uint256 private constant DEFAULT_POOL_SWAP_FEE = 0;
    uint256 private constant DEFAULT_PROTOCOL_SWAP_FEE = 0;
    uint256 private constant DEFAULT_PROTOCOL_YIELD_FEE = 0;

    IVault private immutable _vault;

    constructor(IVault vault, uint256 pauseWindowDuration) FactoryWidePauseWindow(pauseWindowDuration) {
        _vault = vault;
    }

    function registerTestPool(address pool, TokenConfig[] memory tokenConfig, address poolCreator) external {
        _vault.registerPool(
            pool,
            tokenConfig,
            DEFAULT_POOL_SWAP_FEE,
            DEFAULT_PROTOCOL_SWAP_FEE,
            DEFAULT_PROTOCOL_YIELD_FEE,
            getNewPoolPauseWindowEndTime(),
            PoolRoleAccounts({ pauseManager: address(0), swapFeeManager: address(0), poolCreator: poolCreator }),
            PoolConfigBits.wrap(0).toPoolConfig().hooks,
            LiquidityManagement({
                disableUnbalancedLiquidity: false,
                enableAddLiquidityCustom: true,
                enableRemoveLiquidityCustom: true
            })
        );
    }

    function registerGeneralTestPool(
        address pool,
        TokenConfig[] memory tokenConfig,
        uint256 poolSwapFee,
        uint256 protocolSwapFee,
        uint256 protocolYieldFee,
        uint256 pauseWindowDuration,
        PoolRoleAccounts memory roleAccounts
    ) external {
        _vault.registerPool(
            pool,
            tokenConfig,
            poolSwapFee,
            protocolSwapFee,
            protocolYieldFee,
            block.timestamp + pauseWindowDuration,
            roleAccounts,
            PoolConfigBits.wrap(0).toPoolConfig().hooks,
            LiquidityManagement({
                disableUnbalancedLiquidity: false,
                enableAddLiquidityCustom: true,
                enableRemoveLiquidityCustom: true
            })
        );
    }

    function registerPool(
        address pool,
        TokenConfig[] memory tokenConfig,
        PoolRoleAccounts memory roleAccounts,
        PoolHooks calldata poolHooks,
        LiquidityManagement calldata liquidityManagement
    ) external {
        _vault.registerPool(
            pool,
            tokenConfig,
            DEFAULT_POOL_SWAP_FEE,
            DEFAULT_PROTOCOL_SWAP_FEE,
            DEFAULT_PROTOCOL_YIELD_FEE,
            getNewPoolPauseWindowEndTime(),
            roleAccounts,
            poolHooks,
            liquidityManagement
        );
    }

    function registerPoolWithSwapFee(
        address pool,
        TokenConfig[] memory tokenConfig,
        uint256 swapFeePercentage,
        PoolHooks calldata poolHooks,
        LiquidityManagement calldata liquidityManagement
    ) external {
        _vault.registerPool(
            pool,
            tokenConfig,
            swapFeePercentage,
            DEFAULT_PROTOCOL_SWAP_FEE,
            DEFAULT_PROTOCOL_YIELD_FEE,
            getNewPoolPauseWindowEndTime(),
            PoolRoleAccounts({ pauseManager: address(0), swapFeeManager: address(0), poolCreator: address(0) }),
            poolHooks,
            liquidityManagement
        );
    }

    // For tests; otherwise can't get the exact event arguments.
    function registerPoolAtTimestamp(
        address pool,
        TokenConfig[] memory tokenConfig,
        uint256 timestamp,
        PoolRoleAccounts memory roleAccounts,
        PoolHooks calldata poolHooks,
        LiquidityManagement calldata liquidityManagement
    ) external {
        _vault.registerPool(
            pool,
            tokenConfig,
            DEFAULT_POOL_SWAP_FEE,
            DEFAULT_PROTOCOL_SWAP_FEE,
            DEFAULT_PROTOCOL_YIELD_FEE,
            timestamp,
            roleAccounts,
            poolHooks,
            liquidityManagement
        );
    }
}
