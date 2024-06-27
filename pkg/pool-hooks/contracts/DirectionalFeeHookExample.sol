// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { BasePoolHooks } from "@balancer-labs/v3-vault/contracts/BasePoolHooks.sol";

contract DirectionalFeeHookExample is BasePoolHooks {
    // only stable pools from the allowed factory are able to register and use this hook
    address private immutable _allowedStablePoolFactory;

    constructor(
        IVault vault,
        address allowedStablePoolFactory,
        address veBAL,
        address trustedRouter
    ) BasePoolHooks(vault) {
        _allowedStablePoolFactory = allowedStablePoolFactory;
        _trustedRouter = trustedRouter;
        _veBAL = IERC20(veBAL);
    }

    /// @inheritdoc IHooks
    function onRegister(
        address factory,
        address pool,
        TokenConfig[] memory,
        LiquidityManagement calldata liquidityManagement
    ) external view override onlyVault returns (bool) {
        // This hook allows only stable pools to implement it
        return factory == _allowedStablePoolFactory && IBasePoolFactory(factory).isPoolFromFactory(pool);
    }

    /// @inheritdoc IHooks
    function getHookFlags() external pure override returns (IHooks.HookFlags memory hookFlags) {
        hookFlags.shouldCallComputeDynamicSwapFee = true;
    }

    /// @inheritdoc IHooks
    function onComputeDynamicSwapFee(
        IBasePool.PoolSwapParams calldata params,
        address pool,
        uint256 staticSwapFeePercentage
    ) external view override returns (bool, uint256) {
        return (true, staticSwapFeePercentage);
    }
}
