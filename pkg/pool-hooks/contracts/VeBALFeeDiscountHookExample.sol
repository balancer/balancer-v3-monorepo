// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IRouterCommon } from "@balancer-labs/v3-interfaces/contracts/vault/IRouterCommon.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { LiquidityManagement, TokenConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { BasePoolHooks } from "@balancer-labs/v3-vault/contracts/BasePoolHooks.sol";

contract VeBALFeeDiscountHookExample is BasePoolHooks {
    // only pools from the allowedFactory are able to register and use this hook
    address private _allowedFactory;
    IERC20 private _veBAL;

    constructor(IVault vault, address allowedFactory, address veBAL) BasePoolHooks(vault) {
        // verify that this hook can only be used by pools created from `_allowedFactory`
        _allowedFactory = allowedFactory;
        _veBAL = IERC20(veBAL);
    }

    /// @inheritdoc IHooks
    function getHookFlags() external pure override returns (IHooks.HookFlags memory hookFlags) {
        return
            IHooks.HookFlags({
                enableHookAdjustedAmounts: false,
                shouldCallBeforeInitialize: false,
                shouldCallAfterInitialize: false,
                shouldCallComputeDynamicSwapFee: true,
                shouldCallBeforeSwap: false,
                shouldCallAfterSwap: false,
                shouldCallBeforeAddLiquidity: false,
                shouldCallAfterAddLiquidity: false,
                shouldCallBeforeRemoveLiquidity: false,
                shouldCallAfterRemoveLiquidity: false
            });
    }

    /// @inheritdoc IHooks
    function onRegister(
        address factory,
        address pool,
        TokenConfig[] memory tokenConfig,
        LiquidityManagement calldata liquidityManagement
    ) external override returns (bool) {
        // reverts if the pool is not from the allowed factory
        return factory == _allowedFactory;
    }

    /// @inheritdoc IHooks
    function onComputeDynamicSwapFee(
        IBasePool.PoolSwapParams calldata params,
        uint256 staticSwapFeePercentage
    ) external view override returns (bool, uint256) {
        address user = IRouterCommon(params.router).getSender();

        if (_veBAL.balanceOf(user) == 0) {
            return (true, staticSwapFeePercentage);
        }
        // If user has veBAL, apply 50% discount in the current fee
        return (true, staticSwapFeePercentage / 2);
    }
}
