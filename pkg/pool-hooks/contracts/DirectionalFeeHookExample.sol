// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IBasePoolFactory } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePoolFactory.sol";
import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { LiquidityManagement, TokenConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { BasePoolHooks } from "@balancer-labs/v3-vault/contracts/BasePoolHooks.sol";

contract DirectionalFeeHookExample is BasePoolHooks {
    using FixedPoint for uint256;

    // only stable pools from the allowed factory are able to register and use this hook
    address private immutable _allowedStablePoolFactory;

    constructor(IVault vault, address allowedStablePoolFactory) BasePoolHooks(vault) {
        _allowedStablePoolFactory = allowedStablePoolFactory;
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
        // Get pool balances
        (IERC20[] memory tokens, , , uint256[] memory lastLiveBalances) = _vault.getPoolTokenInfo(pool);

        uint256 finalBalanceTokenIn = lastLiveBalances[params.indexIn] + params.amountGivenScaled18;
        uint256 finalBalanceTokenOut = lastLiveBalances[params.indexOut] - params.amountGivenScaled18;
        uint256 totalLiquidity = finalBalanceTokenIn + finalBalanceTokenOut;

        if (finalBalanceTokenIn > finalBalanceTokenOut) {
            // pool is farther from equilibrium
            // TODO explain
            uint256 diff = finalBalanceTokenIn - finalBalanceTokenOut;
            // If diff is close to totalLiquidity, we charge a very large swap fee because the swap is moving the pool
            // balances to the edge
            uint256 feePercentage = diff.divDown(totalLiquidity);
            return (true, feePercentage > staticSwapFeePercentage ? feePercentage : staticSwapFeePercentage);
        }

        // pool is nearer equilibrium, so charge the usual staticSwapFeePercentage
        return (true, staticSwapFeePercentage);
    }
}
