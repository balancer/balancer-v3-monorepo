// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IBasePoolFactory } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePoolFactory.sol";
import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IRouterCommon } from "@balancer-labs/v3-interfaces/contracts/vault/IRouterCommon.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { LiquidityManagement, TokenConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { BasePoolHooks } from "@balancer-labs/v3-vault/contracts/BasePoolHooks.sol";

contract VeBALFeeDiscountHookExample is BasePoolHooks {
    // only pools from the allowedFactory are able to register and use this hook
    address private immutable _allowedFactory;
    // only calls from a trusted routers are allowed to call this hook, because the hook relies on the getSender
    // implementation to work properly
    address private immutable _trustedRouter;
    IERC20 private immutable _veBAL;

    constructor(IVault vault, address allowedFactory, address veBAL, address trustedRouter) BasePoolHooks(vault) {
        _allowedFactory = allowedFactory;
        _trustedRouter = trustedRouter;
        _veBAL = IERC20(veBAL);
    }

    /// @inheritdoc IHooks
    function getHookFlags() external pure override returns (IHooks.HookFlags memory hookFlags) {
        hookFlags.shouldCallComputeDynamicSwapFee = true;
    }

    /// @inheritdoc IHooks
    function onRegister(
        address factory,
        address pool,
        TokenConfig[] memory,
        LiquidityManagement calldata
    ) external view override returns (bool) {
        // This hook implements a restrictive approach, where we check if the factory is an allowed factory and if
        // the pool was created by the allowed factory. Since we only use onComputeDynamicSwapFee, this might be an
        // overkill in real applications because the pool math doesn't play a role in the discount calculation.
        return factory == _allowedFactory && IBasePoolFactory(factory).isPoolFromFactory(pool);
    }

    /// @inheritdoc IHooks
    function onComputeDynamicSwapFee(
        IBasePool.PoolSwapParams calldata params,
        address,
        uint256 staticSwapFeePercentage
    ) external view override returns (bool, uint256) {
        // If the router is not trusted, does not apply the veBAL discount because getSender() may be manipulated by a
        // malicious router.
        if (params.router != _trustedRouter) {
            return (true, staticSwapFeePercentage);
        }

        address user = IRouterCommon(params.router).getSender();

        // If user has veBAL, apply a 50% discount to the current fee (divides fees by 2)
        if (_veBAL.balanceOf(user) > 0) {
            return (true, staticSwapFeePercentage / 2);
        }

        return (true, staticSwapFeePercentage);
    }
}
