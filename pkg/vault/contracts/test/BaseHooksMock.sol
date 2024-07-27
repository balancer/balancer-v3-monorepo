// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import "../BaseHooks.sol";

contract BaseHooksMock is BaseHooks {
    constructor(IVault vault) BaseHooks(vault) {
        // solhint-disable-previous-line no-empty-blocks
    }

    /// @inheritdoc IHooks
    function onRegister(
        address factory,
        address pool,
        TokenConfig[] memory tokenConfig,
        LiquidityManagement calldata liquidityManagement
    ) public override returns (bool) {
        return super.onRegister(factory, pool, tokenConfig, liquidityManagement);
    }

    /// @inheritdoc IHooks
    function getHookFlags() public pure override returns (HookFlags memory hookFlags) {
        // This function is abstract, so there's nothing to call here.
        return hookFlags;
    }

    /// @inheritdoc IHooks
    function onBeforeInitialize(uint256[] memory exactAmountsIn, bytes memory userData) public override returns (bool) {
        return super.onBeforeInitialize(exactAmountsIn, userData);
    }

    /// @inheritdoc IHooks
    function onAfterInitialize(
        uint256[] memory exactAmountsIn,
        uint256 bptAmountOut,
        bytes memory userData
    ) public override returns (bool) {
        return super.onAfterInitialize(exactAmountsIn, bptAmountOut, userData);
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
    ) public override returns (bool) {
        return
            super.onBeforeAddLiquidity(
                router,
                pool,
                kind,
                maxAmountsInScaled18,
                minBptAmountOut,
                balancesScaled18,
                userData
            );
    }

    /// @inheritdoc IHooks
    function onAfterAddLiquidity(
        address router,
        address pool,
        AddLiquidityKind kind,
        uint256[] memory amountsInScaled18,
        uint256[] memory amountsInRaw,
        uint256 bptAmountOut,
        uint256[] memory balancesScaled18,
        bytes memory userData
    ) public override returns (bool, uint256[] memory) {
        return
            super.onAfterAddLiquidity(
                router,
                pool,
                kind,
                amountsInScaled18,
                amountsInRaw,
                bptAmountOut,
                balancesScaled18,
                userData
            );
    }

    /// @inheritdoc IHooks
    function onBeforeRemoveLiquidity(
        address router,
        address pool,
        RemoveLiquidityKind kind,
        uint256 maxBptAmountIn,
        uint256[] memory minAmountsOutScaled18,
        uint256[] memory balancesScaled18,
        bytes memory userData
    ) public override returns (bool) {
        return
            super.onBeforeRemoveLiquidity(
                router,
                pool,
                kind,
                maxBptAmountIn,
                minAmountsOutScaled18,
                balancesScaled18,
                userData
            );
    }

    /// @inheritdoc IHooks
    function onAfterRemoveLiquidity(
        address router,
        address pool,
        RemoveLiquidityKind kind,
        uint256 bptAmountIn,
        uint256[] memory amountsOutScaled18,
        uint256[] memory amountsOutRaw,
        uint256[] memory balancesScaled18,
        bytes memory userData
    ) public override returns (bool, uint256[] memory) {
        return
            super.onAfterRemoveLiquidity(
                router,
                pool,
                kind,
                bptAmountIn,
                amountsOutScaled18,
                amountsOutRaw,
                balancesScaled18,
                userData
            );
    }

    /// @inheritdoc IHooks
    function onBeforeSwap(PoolSwapParams calldata params, address pool) public override returns (bool) {
        return super.onBeforeSwap(params, pool);
    }

    /// @inheritdoc IHooks
    function onAfterSwap(AfterSwapParams calldata params) public override returns (bool, uint256) {
        return super.onAfterSwap(params);
    }

    /// @inheritdoc IHooks
    function onComputeDynamicSwapFeePercentage(
        PoolSwapParams calldata params,
        address pool,
        uint256 staticSwapFeePercentage
    ) public view override returns (bool, uint256) {
        return super.onComputeDynamicSwapFeePercentage(params, pool, staticSwapFeePercentage);
    }
}
