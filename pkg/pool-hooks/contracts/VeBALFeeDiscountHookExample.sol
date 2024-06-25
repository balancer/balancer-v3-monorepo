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
    address private _allowedFactory;
    address private _trustedRouter;
    IERC20 private _veBAL;

    /**
     * @dev This hook checks the transaction sender's veBAL balance, using the address supplied by the router.
     * Since routers are permissionless, and a malicious router might supply an incorrect address, we need to check
     * that the router calling the hook is "trusted" to supply the correct sender.
     */
    error RouterNotTrustedByHook(address hook, address router);

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
        // This hook can only be used by pools created from `_allowedFactory`.
        return factory == _allowedFactory && IBasePoolFactory(factory).isPoolFromFactory(pool);
    }

    /// @inheritdoc IHooks
    function onComputeDynamicSwapFee(
        IBasePool.PoolSwapParams calldata params,
        uint256 staticSwapFeePercentage
    ) external view override onlyTrustedRouter(params.router) returns (bool, uint256) {
        address user = IRouterCommon(params.router).getSender();

        if (_veBAL.balanceOf(user) == 0) {
            return (true, staticSwapFeePercentage);
        }
        // If user has veBAL, apply a 50% discount to the current fee
        return (true, staticSwapFeePercentage / 2);
    }

    modifier onlyTrustedRouter(address router) {
        // Since the router passes the user address through getSender(), the hook must trust it. Otherwise, any router
        // could implement a getSender() returning an address that holds veBAL.
        if (router != _trustedRouter) {
            revert RouterNotTrustedByHook(address(this), router);
        }
        _;
    }
}
