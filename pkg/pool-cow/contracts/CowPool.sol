// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { ICowPool } from "@balancer-labs/v3-interfaces/contracts/pool-cow/ICowPool.sol";
import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { WeightedPool } from "@balancer-labs/v3-pool-weighted/contracts/WeightedPool.sol";

import { BaseHooks } from "@balancer-labs/v3-vault/contracts/BaseHooks.sol";

import { CowPoolFactory } from "./CowPoolFactory.sol";

contract CowPool is ICowPool, BaseHooks, WeightedPool {
    address internal _trustedCowRouter;
    CowPoolFactory internal _cowPoolFactory;

    constructor(
        WeightedPool.NewPoolParams memory params,
        IVault vault,
        address trustedCowRouter
    ) WeightedPool(params, vault) {
        _cowPoolFactory = CowPoolFactory(msg.sender);
        _setTrustedCowRouter(trustedCowRouter);
    }

    /********************************************************
                          Trusted Router
    ********************************************************/

    /// @inheritdoc ICowPool
    function getTrustedCowRouter() external view returns (address) {
        return _trustedCowRouter;
    }

    /// @inheritdoc ICowPool
    function refreshTrustedCowRouter() external {
        _setTrustedCowRouter(_cowPoolFactory.getTrustedCowRouter());
    }

    /********************************************************
                     Dynamic and Immutable Data
    ********************************************************/

    /// @inheritdoc ICowPool
    function getCowPoolDynamicData() external view returns (CoWPoolDynamicData memory data) {
        data.balancesLiveScaled18 = _vault.getCurrentLiveBalances(address(this));
        (, data.tokenRates) = _vault.getPoolTokenRates(address(this));
        data.staticSwapFeePercentage = _vault.getStaticSwapFeePercentage((address(this)));
        data.totalSupply = totalSupply();
        data.trustedCowRouter = _trustedCowRouter;

        PoolConfig memory poolConfig = _vault.getPoolConfig(address(this));
        data.isPoolInitialized = poolConfig.isPoolInitialized;
        data.isPoolPaused = poolConfig.isPoolPaused;
        data.isPoolInRecoveryMode = poolConfig.isPoolInRecoveryMode;
    }

    /// @inheritdoc ICowPool
    function getCowPoolImmutableData() external view returns (CoWPoolImmutableData memory data) {
        data.tokens = _vault.getPoolTokens(address(this));
        (data.decimalScalingFactors, ) = _vault.getPoolTokenRates(address(this));
        data.normalizedWeights = _getNormalizedWeights();
    }

    /********************************************************
                              Hooks
    ********************************************************/

    /// @inheritdoc IHooks
    function onRegister(
        address factory,
        address pool,
        TokenConfig[] memory,
        LiquidityManagement calldata liquidityManagement
    ) public view override returns (bool) {
        return
            pool == address(this) &&
            factory == address(_cowPoolFactory) &&
            liquidityManagement.enableDonation == true &&
            liquidityManagement.disableUnbalancedLiquidity == true;
    }

    /// @inheritdoc IHooks
    function getHookFlags() public pure override returns (HookFlags memory hookFlags) {
        hookFlags.shouldCallBeforeSwap = true;
        hookFlags.shouldCallBeforeAddLiquidity = true;
    }

    /// @inheritdoc IHooks
    function onBeforeSwap(PoolSwapParams calldata params, address) public view override returns (bool) {
        // It only allows a swap from the trusted router, which is a CoW AMM Router.
        return params.router == _trustedCowRouter;
    }

    /// @inheritdoc IHooks
    function onBeforeAddLiquidity(
        address router,
        address,
        AddLiquidityKind kind,
        uint256[] memory,
        uint256,
        uint256[] memory,
        bytes memory
    ) public view override returns (bool success) {
        // Donations from routers that are not the trusted CoW AMM Router should be blocked. Any other liquidity
        // operation is allowed from any router. However, the factory of this pool also disables unbalanced liquidity
        // operations.
        return kind != AddLiquidityKind.DONATION || router == _trustedCowRouter;
    }

    /********************************************************
                        Private Helpers
    ********************************************************/

    // This assumes the trusted CoW Router address has been validated externally (e.g., in the factory).
    function _setTrustedCowRouter(address trustedCowRouter) private {
        _trustedCowRouter = trustedCowRouter;

        emit CowTrustedRouterChanged(_trustedCowRouter);
    }
}
