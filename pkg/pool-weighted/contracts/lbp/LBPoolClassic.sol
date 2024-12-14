// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { GradualValueChange } from "../lib/GradualValueChange.sol";
import { BaseLBPool } from "./BaseLBPool.sol";

/**
 * @notice LBPool with the classic implementation of LBPools from Balancer v2.
 * Features include manually enabling/disabling swaps, no gradual update limits, and no
 * limits on the number of joins/exits.
 */
contract LBPoolClassic is BaseLBPool {
    using SafeCast for *;
    
    bool _swapEnabled;

    /**
     * @notice Emitted when the owner enables or disables swaps.
     * @param swapEnabled True if we are enabling swaps
     */
    event SwapEnabledSet(bool swapEnabled);

    constructor(
        NewPoolParams memory params,
        IVault vault,
        address owner,
        bool swapEnabledOnStart,
        address trustedRouter
    ) BaseLBPool(params, vault, owner, trustedRouter) {
        _setSwapEnabled(swapEnabledOnStart);
    }

    /*******************************************************************************
                                Permissioned Functions
    *******************************************************************************/

    /**
     * @notice Enable/disable trading.
     * @dev This is a permissioned function that can only be called by the owner.
     * @param swapEnabled True if trading should be enabled
     */
    function setSwapEnabled(bool swapEnabled) external onlyOwner {
        _setSwapEnabled(swapEnabled);
    }

    /**
     * @notice Start a gradual weight change. Weights will change smoothly from current values to `endWeights`.
     * @dev This is a permissioned function that can only be called by the owner.
     * If the `startTime` is in the past, the weight change will begin immediately.
     *
     * @param startTime The timestamp when the weight change will start
     * @param endTime  The timestamp when the weights will reach their final values
     * @param endWeights The final values of the weights
     */
    function updateWeightsGradually(
        uint256 startTime,
        uint256 endTime,
        uint256[] memory endWeights
    ) external onlyOwner {
        InputHelpers.ensureInputLengthMatch(_NUM_TOKENS, endWeights.length);

        if (endWeights[0] < _MIN_WEIGHT || endWeights[1] < _MIN_WEIGHT) {
            revert MinWeight();
        }
        if (endWeights[0] + endWeights[1] != FixedPoint.ONE) {
            revert NormalizedWeightInvariant();
        }

        // Ensure startTime >= now.
        startTime = GradualValueChange.resolveStartTime(startTime, endTime);

        // The SafeCast ensures `endTime` can't overflow.
        _startGradualWeightChange(startTime.toUint32(), endTime.toUint32(), _getNormalizedWeights(), endWeights);
    }

    /*******************************************************************************
                                  Internal Functions
    *******************************************************************************/

    function _getPoolSwapEnabled() internal override view returns (bool) {
        return _swapEnabled;
    }

    function _setSwapEnabled(bool swapEnabled) private {
        _swapEnabled = swapEnabled;

        emit SwapEnabledSet(swapEnabled);
    }
}
