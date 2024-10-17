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
     * You can think of the invariant as a measure of the "value" of the pool, which is related to the total liquidity
     * (i.e., the "BPT rate" is `invariant` / `totalSupply`). Two critical properties must hold:
     *
     * 1) The invariant should not change due to a swap. In practice, it can *increase* due to swap fees, which
     * effectively add liquidity after the swap - but it should never decrease.
     *
     * 2) The invariant must be "linear"; i.e., increasing the balances proportionally must increase the invariant in
     * the same proportion: inv(a * n,b * n,c * n) = inv(a, b, c) * n
     *
     * Property #1 is required to prevent "round trip" paths that drain value from the pool (and all LP shareholders).
     * Intuitively, an accurate pricing algorithm ensures the user gets an equal value of token out given token in, so
     * the total value should not change.
     *
     * Property #2 is essential for the "fungibility" of LP shares. If it did not hold, then different users depositing
     * the same total value would get a different number of LP shares. In that case, LP shares would not be
     * interchangeable, as they must be in a fair DEX.
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
