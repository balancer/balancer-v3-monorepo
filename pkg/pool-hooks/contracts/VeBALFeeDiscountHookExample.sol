// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IBasePoolFactory } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePoolFactory.sol";
import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IRouterCommon } from "@balancer-labs/v3-interfaces/contracts/vault/IRouterCommon.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import {
    LiquidityManagement,
    TokenConfig,
    PoolSwapParams,
    HookFlags
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { BaseHooks } from "@balancer-labs/v3-vault/contracts/BaseHooks.sol";

/**
 * @notice Hook that gives a swap fee discount to veBAL holders.
 * @dev Uses the dynamic fee mechanism to give a 50% discount on swap fees.
 */
contract VeBALFeeDiscountHookExample is BaseHooks {
    // Only pools from a specific factory are able to register and use this hook.
    address private immutable _allowedFactory;
    // Only trusted routers are allowed to call this hook, because the hook relies on the `getSender` implementation
    // implementation to work properly.
    address private immutable _trustedRouter;
    // The gauge token received from staking the 80/20 BAL/WETH pool token.
    IERC20 private immutable _veBAL;

    constructor(IVault vault, address allowedFactory, address veBAL, address trustedRouter) BaseHooks(vault) {
        _allowedFactory = allowedFactory;
        _trustedRouter = trustedRouter;
        _veBAL = IERC20(veBAL);
    }

    /// @inheritdoc IHooks
    function getHookFlags() public pure override returns (HookFlags memory hookFlags) {
        hookFlags.shouldCallComputeDynamicSwapFee = true;
    }

    /// @inheritdoc IHooks
    function onRegister(
        address factory,
        address pool,
        TokenConfig[] memory,
        LiquidityManagement calldata
    ) public view override onlyVault returns (bool) {
        // This hook implements a restrictive approach, where we check if the factory is an allowed factory and if
        // the pool was created by the allowed factory. Since we only use onComputeDynamicSwapFeePercentage, this
        // might be an overkill in real applications because the pool math doesn't play a role in the discount
        // calculation.
        return factory == _allowedFactory && IBasePoolFactory(factory).isPoolFromFactory(pool);
    }

    /// @inheritdoc IHooks
    function onComputeDynamicSwapFeePercentage(
        PoolSwapParams calldata params,
        address,
        uint256 staticSwapFeePercentage
    ) public view override onlyVault returns (bool, uint256) {
        // If the router is not trusted, do not apply the veBAL discount. `getSender` may be manipulated by a
        // malicious router.
        if (params.router != _trustedRouter) {
            return (true, staticSwapFeePercentage);
        }

        address user = IRouterCommon(params.router).getSender();

        // If user has veBAL, apply a 50% discount to the current fee.
        if (_veBAL.balanceOf(user) > 0) {
            return (true, staticSwapFeePercentage / 2);
        }

        return (true, staticSwapFeePercentage);
    }
}
