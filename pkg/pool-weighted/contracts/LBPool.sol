// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { WeightedPool } from "./WeightedPool.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { GradualValueChange } from "../lib/GradualValueChange.sol";

/// @notice Basic Weighted Pool with immutable weights.
contract LBPool is WeightedPool, Ownable {

    uint256 private constant _NUM_TOKENS = 2;

    // Since we have max 2 tokens and the weights must sum to 1, we only need to track one weight
    struct PoolState {
        uint60 startTime;
        uint60 endTime;
        uint64 startWeight0;
        uint64 endWeight0;
        bool isPaused;
    }
    PoolState private _poolState;

    /// @dev Indicates end time before start time.
    error EndTimeBeforeStartTime();

    constructor(NewPoolParams memory params, IVault vault, bool startPaused, address owner) WeightedPool(params, vault) Ownable(owner) {
        _isPaused = startPaused;

        InputHelpers.ensureInputLengthMatch(_NUM_TOKENS, params.numTokens);
        // WeightedPool takes care of numTokens == normalizedWeights.length

        uint256 currentTime = block.timestamp;
        _startGradualWeightChange(currentTime, currentTime, normalizedWeights, normalizedWeights);

    }

    function updateWeightsGradually(
        uint256 startTime,
        uint256 endTime,
        uint256[] memory endWeights
    ) external view onlyOwner {
        InputHelpers.ensureInputLengthMatch(_NUM_TOKENS, endWeights.length);

        startTime = GradualValueChange.resolveStartTime(startTime, endTime);
        _startGradualWeightChange(startTime, endTime, _getNormalizedWeights(), endWeights);
    }
    
    function _getNormalizedWeights() internal view override returns (uint256[] memory) {
        uint256[] memory normalizedWeights = new uint256[](_NUM_TOKENS);

        normalizedWeights[0] = _getNormalizedWeight0();
        normalizedWeights[1] = FixedPoint.ONE - normalizedWeights[0];
        return normalizedWeights;
    }

    function _getNormalizedWeight(uint256 tokenIndex) internal view virtual override returns (uint256) {
        uint256 normalizedWeight0 = _getNormalizedWeight0()

        // prettier-ignore
        if (tokenIndex == 0) { return normalizedWeight0; }
        else if (tokenIndex == 1) { FixedPoint.ONE - normalizedWeight0; }
        else {
            revert IVaultErrors.InvalidToken();
        }
    }

    function _getNormalizedWeight0() internal view virtual returns (uint256) {
        PoolState poolState = _poolState;
        uint256 pctProgress = _getWeightChangeProgress(poolState);
        return GradualValueChange.interpolateValue(poolState.startWeight0, poolState.endWeight0, pctProgress);
    }

    function _getWeightChangeProgress(PoolState poolState) internal view returns (uint256) {
        return GradualValueChange.calculateValueChangeProgress(poolState.startTime, poolState.endTime);
    }
}
