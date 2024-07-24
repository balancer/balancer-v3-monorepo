// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IBasePoolFactory } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePoolFactory.sol";
import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import {
    LiquidityManagement,
    TokenConfig,
    PoolSwapParams,
    HookFlags
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { BaseHooks } from "@balancer-labs/v3-vault/contracts/BaseHooks.sol";

/**
 * @notice Increase the swap fee percentage on trades that move pools away from equilibrium.
 * @dev This is most applicable to stable pools with approximately linear math
 * (e.g., with higher amplificationFactor values).
 *
 * This hook implements `onComputeDynamicSwapFeePercentage`, which is called before each swap to determine the final
 * value of the swap fee percentage. If a trade moves the pool balances toward equilibrium, this hook returns the
 * regular static swap fee. Otherwise, it charges a larger fee, approaching 100% as the balance of `tokenOut`
 * approaches zero.
 *
 * Note that this is just an example to illustrate the concept. A real hook would likely be more sophisticated,
 * perhaps establishing a range within which swaps charge the standard fee, and ensuring a smooth and symmetrical
 * fee increase on either side.
 */
contract DirectionalFeeHookExample is BaseHooks {
    using FixedPoint for uint256;

    // Only stable pools from the allowed factory are able to register and use this hook.
    address private immutable _allowedStablePoolFactory;

    constructor(IVault vault, address allowedStablePoolFactory) BaseHooks(vault) {
        // Although the hook allows any factory to be registered during deployment, it should be a stable pool factory.
        _allowedStablePoolFactory = allowedStablePoolFactory;
    }

    /// @inheritdoc IHooks
    function onRegister(
        address factory,
        address pool,
        TokenConfig[] memory,
        LiquidityManagement calldata
    ) public view override onlyVault returns (bool) {
        // This hook only allows pools deployed by `_allowedStablePoolFactory` to register it.
        return factory == _allowedStablePoolFactory && IBasePoolFactory(factory).isPoolFromFactory(pool);
    }

    /// @inheritdoc IHooks
    function getHookFlags() public pure override returns (HookFlags memory hookFlags) {
        hookFlags.shouldCallComputeDynamicSwapFee = true;
    }

    /// @inheritdoc IHooks
    function onComputeDynamicSwapFeePercentage(
        PoolSwapParams calldata params,
        address pool,
        uint256 staticSwapFeePercentage
    ) public view override onlyVault returns (bool, uint256) {
        // Get pool balances
        (, , , uint256[] memory lastBalancesLiveScaled18) = _vault.getPoolTokenInfo(pool);

        uint256 calculatedSwapFeePercentage = _calculatedExpectedSwapFeePercentage(
            lastBalancesLiveScaled18,
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
     *  changed proportionally. This approximation is just to illustrate this hook in a simple manner, but is
     *  also reasonable, since stable pools behave linearly near equilibrium. Also, this example requires
     *  the rates to be 1:1, which is common among assets that are pegged around the same value, such as USD.
     *  The charged fee percentage is:
     *
     *  (distance between balances of token in and token out) / (total liquidity of both tokens)
     *
     *  For example, if token in has a final balance of 100, and token out has a final balance of 40, the
     *  calculated swap fee percentage is (100 - 40) / (140) = 60/140 = 42.85%
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
            // If `diff` is close to `totalLiquidity`, we charge a very large swap fee because the swap is moving the
            // pool balances to the edge.
            feePercentage = diff.divDown(totalLiquidity);
        }
    }
}
