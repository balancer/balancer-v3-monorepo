// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { ISwapFeePercentageBounds } from "./ISwapFeePercentageBounds.sol";
import { IUnbalancedLiquidityInvariantRatioBounds } from "./IUnbalancedLiquidityInvariantRatioBounds.sol";
import { PoolSwapParams, Rounding, SwapKind } from "./VaultTypes.sol";

/**
 * @notice Base interface for a Balancer Pool.
 * @dev All pool types should implement this interface. Note that it also requires implementation of:
 * - `ISwapFeePercentageBounds` to specify the minimum and maximum swap fee percentages.
 * - `IUnbalancedLiquidityInvariantRatioBounds` to specify how much the invariant can change during an unbalanced
 * liquidity operation.
 */
interface IBasePool is ISwapFeePercentageBounds, IUnbalancedLiquidityInvariantRatioBounds {
    /***************************************************************************
                                   Invariant
    ***************************************************************************/

    /**
     * @notice Computes the pool's invariant.
     * @dev This function computes the invariant based on current balances (and potentially other pool state).
     * The rounding direction must be respected for the Vault to round in the pool's favor when calling this function.
     * If the invariant computation involves no precision loss (e.g. simple sum of balances), the same result can be
     * returned for both rounding directions.
     *
     * @param balancesLiveScaled18 Token balances after paying yield fees, applying decimal scaling and rates
     * @param rounding Rounding direction to consider when computing the invariant
     * @return invariant The calculated invariant of the pool, represented as a uint256
     */
    function computeInvariant(
        uint256[] memory balancesLiveScaled18,
        Rounding rounding
    ) external view returns (uint256 invariant);

    /**
     * @dev Computes the new balance of a token after an operation, given the invariant growth ratio and all other
     * balances. Similar to V2's `_getTokenBalanceGivenInvariantAndAllOtherBalances` in StableMath.
     * The pool must round up for the Vault to round in the protocol's favor when calling this function.
     *
     * @param balancesLiveScaled18 Token balances after paying yield fees, applying decimal scaling and rates
     * @param tokenInIndex The index of the token we're computing the balance for, sorted in token registration order
     * @param invariantRatio The ratio of the new invariant (after an operation) to the old
     * @return newBalance The new balance of the selected token, after the operation
     */
    function computeBalance(
        uint256[] memory balancesLiveScaled18,
        uint256 tokenInIndex,
        uint256 invariantRatio
    ) external view returns (uint256 newBalance);

    /***************************************************************************
                                       Swaps
    ***************************************************************************/

    /**
     * @notice Execute a swap in the pool.
     * @param params Swap parameters (see above for struct definition)
     * @return amountCalculatedScaled18 Calculated amount for the swap operation
     */
    function onSwap(PoolSwapParams calldata params) external returns (uint256 amountCalculatedScaled18);
}
