// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IBasePoolFactory } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePoolFactory.sol";
import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { LiquidityManagement, TokenConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { BaseHooks } from "@balancer-labs/v3-vault/contracts/BaseHooks.sol";

contract DirectionalFeeHookExample is BaseHooks {
    using FixedPoint for uint256;

    // only stable pools from the allowed factory are able to register and use this hook
    address private immutable _allowedStablePoolFactory;

    constructor(IVault vault, address allowedStablePoolFactory) BaseHooks(vault) {
        _allowedStablePoolFactory = allowedStablePoolFactory;
    }

    /// @inheritdoc IHooks
    function onRegister(
        address factory,
        address pool,
        TokenConfig[] memory,
        LiquidityManagement calldata
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
        (, , , uint256[] memory lastLiveBalances) = _vault.getPoolTokenInfo(pool);

        uint256 calculatedSwapFeePercentage = _calculatedExpectedSwapFeePercentage(
            lastLiveBalances,
            params.amountGivenScaled18,
            params.indexIn,
            params.indexOut
        );

        // Charge the static or calculated fee, whichever is greater.
        return (
            true,
            calculatedSwapFeePercentage > staticSwapFeePercentage
                ? calculatedSwapFeePercentage
                : staticSwapFeePercentage
        );
    }

    /** @notice This example assumes that the pool math is linear and that final balances of token in and out are
     *          changed proportionally. This approximation is just to illustrate this hook in a simple manner, but is
     *          also reasonable, since stable pools behave linearly near the equilibrium. Also, this example requires
     *          the rates to be 1:1, which is common among assets that are pegged around the same value, such as USD.
     *          The charged fee percentage is:
     *
     *          (distance between balances of token in and token out) / (total liquidity of both tokens)
     *
     *          For example, if token in has a final balance of 100, and token out has a final balance of 40, the
     *          calculated swap fee percentage is (100 - 40) / (140) = 60/140 = 42.85%
     */
    function _calculatedExpectedSwapFeePercentage(
        uint256[] memory poolBalances,
        uint256 swapAmount,
        uint256 indexIn,
        uint256 indexOut
    ) private pure returns (uint256 feePercentage) {
        uint256 finalBalanceTokenIn = poolBalances[indexIn] + swapAmount;
        uint256 finalBalanceTokenOut = poolBalances[indexOut] - swapAmount;

        // Pool is farther from equilibrium, charge calculated fee.
        if (finalBalanceTokenIn > finalBalanceTokenOut) {
            uint256 diff = finalBalanceTokenIn - finalBalanceTokenOut;
            uint256 totalLiquidity = finalBalanceTokenIn + finalBalanceTokenOut;
            // If `diff` is close to `totalLiquidity`, we charge a very large swap fee because the swap is moving the pool
            // balances to the edge.
            feePercentage = diff.divDown(totalLiquidity);
        }
    }
}
