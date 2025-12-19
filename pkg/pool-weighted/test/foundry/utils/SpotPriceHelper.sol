// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { ILBPool } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPool.sol";
import { IPoolInfo } from "@balancer-labs/v3-interfaces/contracts/pool-utils/IPoolInfo.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IWeightedPool } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/IWeightedPool.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

/// @dev Compute spot price for Weighted Pools and LB Pools, considering virtual balances in the latter.
library SpotPriceHelper {
    using FixedPoint for uint256;

    /**
     * @notice Compute current spot price for a given pool, in terms of the specified token.
     * E.g. ETH/USDC --> if USDC index is specified, the result is how much USDC for 1 ETH.
     */
    function computeSpotPrice(ILBPool pool, uint256 spotPriceTokenIndex) internal view returns (uint256) {
        // Get effective balances considering virtual balance for LB Pools via the pool (not the vault).
        uint256[] memory effectiveBalancesScaled18 = IPoolInfo(address(pool)).getCurrentLiveBalances();

        uint256[] memory weights = ILBPool(pool).getLBPoolDynamicData().normalizedWeights;

        return _computeSpotPrice(effectiveBalancesScaled18, weights, spotPriceTokenIndex);
    }

    /**
     * @notice Compute current spot price for a given pool, in terms of the specified token.
     * E.g. ETH/USDC --> if USDC index is specified, the result is how much USDC for 1 ETH.
     */
    function computeSpotPrice(IWeightedPool pool, uint256 spotPriceTokenIndex) internal view returns (uint256) {
        uint256[] memory effectiveBalancesScaled18 = IPoolInfo(address(pool)).getCurrentLiveBalances();

        uint256[] memory weights = pool.getNormalizedWeights();

        return _computeSpotPrice(effectiveBalancesScaled18, weights, spotPriceTokenIndex);
    }

    function _computeSpotPrice(
        uint256[] memory balancesScaled18,
        uint256[] memory weights,
        uint256 spotPriceTokenIndex
    ) private pure returns (uint256) {
        (uint256 reserveIdx, uint256 projectIdx) = spotPriceTokenIndex == 0 ? (0, 1) : (1, 0);

        return
            (balancesScaled18[projectIdx].mulDown(weights[reserveIdx])).divDown(
                balancesScaled18[reserveIdx].mulDown(weights[projectIdx])
            );
    }
}
