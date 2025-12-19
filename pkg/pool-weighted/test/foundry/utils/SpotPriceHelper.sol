// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IWeightedPool } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/IWeightedPool.sol";
import { IPoolInfo } from "@balancer-labs/v3-interfaces/contracts/pool-utils/IPoolInfo.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

/// @dev Compute spot price for LBPs and 2-token weighted pools, considering virtual balances for the former.
library SpotPriceHelper {
    using FixedPoint for uint256;

    /**
     * @notice Compute current spot price for a given pool, in terms of the specified reserve token.
     * @dev E.g. ETH/USDC --> if USDC index is specified, the result is how much USDC for 1 ETH. For LBPs, this will
     * be the reserve token. This is used for testing; the regular weighted pools will be "migrated" LBPs, so we can
     * still call it the reserve token.
     */
    function computeSpotPrice(IPoolInfo pool, uint256 reserveTokenIndex) internal view returns (uint256) {
        uint256 projectTokenIndex = reserveTokenIndex == 0 ? 1 : 0;

        uint256[] memory effectiveBalancesScaled18 = IPoolInfo(address(pool)).getCurrentLiveBalances();
        uint256[] memory weights = IWeightedPool(address(pool)).getNormalizedWeights();

        return
            (effectiveBalancesScaled18[projectTokenIndex].mulDown(weights[reserveTokenIndex])).divDown(
                effectiveBalancesScaled18[reserveTokenIndex].mulDown(weights[projectTokenIndex])
            );
    }
}
