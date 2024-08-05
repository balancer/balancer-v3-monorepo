// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

/**
 * @notice Return the minimum/maximum invariant ratios allowed during an unbalanced liquidity operation.
 * @dev The Vault does not enforce any "baseline" bounds on invariant ratios, since such bounds are highly specific
 * and dependent on the math of each pool type. Instead, the Vault reads invariant ratio bounds from the pools.
 * `IBasePool` implements this interface to ensure that new pool developers think about and set these bounds according
 * to their pool type's math.
 *
 * For instance, Balancer Weighted Pool math involves exponentiation (the `pow` function), which uses natural
 * logarithms and a discrete Taylor series expansion to compute x^y values for the 18-decimal floating point numbers
 * used in all Vault computations. See `LogExpMath` and `WeightedMath` for a derivation of the bounds for these pools.
 */
interface IUnbalancedLiquidityInvariantRatioBounds {
    /// @return minimumInvariantRatio The minimum invariant ratio for a pool during unbalanced remove liquidity
    function getMinimumInvariantRatio() external view returns (uint256);

    /// @return maximumInvariantRatio The maximum invariant ratio for a pool during unbalanced add liquidity
    function getMaximumInvariantRatio() external view returns (uint256);
}
