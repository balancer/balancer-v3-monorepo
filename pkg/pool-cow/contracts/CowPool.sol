// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { ICowPool } from "@balancer-labs/v3-interfaces/contracts/cow-pool/ICowPool.sol";
import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import {
    AddLiquidityKind,
    HookFlags,
    PoolSwapParams
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { WeightedPool } from "@balancer-labs/v3-pool-weighted/contracts/WeightedPool.sol";

import { BaseHooks } from "@balancer-labs/v3-vault/contracts/BaseHooks.sol";

import { CowPoolFactory } from "./CowPoolFactory.sol";

contract CowPool is ICowPool, BaseHooks, WeightedPool {
    address internal _trustedCowRouter;
    CowPoolFactory internal _cowPoolFactory;

    constructor(
        WeightedPool.NewPoolParams memory params,
        IVault vault,
        CowPoolFactory cowPoolFactory,
        address trustedCowRouter
    ) WeightedPool(params, vault) {
        _trustedCowRouter = trustedCowRouter;
        _cowPoolFactory = cowPoolFactory;
    }

    /// @inheritdoc ICowPool
    function refreshTrustedCowRouter() external {
        _trustedCowRouter = _cowPoolFactory.getTrustedCowRouter();

        emit CowTrustedRouterRefreshed(_trustedCowRouter);
    }

    /// @inheritdoc IHooks
    function getHookFlags() public view override returns (HookFlags memory hookFlags) {
        hookFlags.shouldCallBeforeSwap = true;
        hookFlags.shouldCallBeforeAddLiquidity = true;
    }

    /// @inheritdoc IHooks
    function onBeforeSwap(PoolSwapParams calldata params, address) public override returns (bool) {
        // It only allows a swap from the trusted router, which is a CoW AMM Router.
        return params.router == _trustedCowRouter;
    }

    /// @inheritdoc IHooks
    function onBeforeAddLiquidity(
        address router,
        address pool,
        AddLiquidityKind kind,
        uint256[] memory maxAmountsInScaled18,
        uint256 minBptAmountOut,
        uint256[] memory balancesScaled18,
        bytes memory userData
    ) external override returns (bool success) {
        // Donations from routers that are not the trusted CoW AMM Router should be blocked. Any other liquidity
        // operation is allowed from any router. However, the factory of this pool also disables unbalanced liquidity
        // operations.
        return kind != AddLiquidityKind.DONATION || router == _trustedCowRouter;
    }
}
