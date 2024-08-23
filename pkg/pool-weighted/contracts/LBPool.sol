// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { WeightedPool } from "./WeightedPool.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IRouterCommon } from "@balancer-labs/v3-interfaces/contracts/vault/IRouterCommon.sol";
import { AddLiquidityKind } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { GradualValueChange } from "./lib/GradualValueChange.sol";
import { WeightValidation } from "./lib/WeightValidation.sol";

/// @notice Inheriting from WeightedPool is only slightly wasteful (setting 2 immutable weights
///     that will not be used later), and it is tremendously helpful for pool validation and
///     any potential future parent class changes.
contract LBPool is WeightedPool, Ownable {
    // Since we have max 2 tokens and the weights must sum to 1, we only need to store one weight
    struct PoolState {
        uint56 startTime;
        uint56 endTime;
        uint64 startWeight0;
        uint64 endWeight0;
        bool swapEnabled;
    }
    PoolState private _poolState;
    uint256 private _swapFeePercentage;

    uint256 private constant _NUM_TOKENS = 2;

    // `{start,end}Time` are `uint56`s. Ensure that no input time (passed as `uint256`) will overflow.
    uint256 private constant _MAX_TIME = type(uint56).max;

    event SwapFeePercentageChanged(uint256 swapFeePercentage);
    event SwapEnabledSet(bool swapEnabled);
    event GradualWeightUpdateScheduled(
        uint256 startTime,
        uint256 endTime,
        uint256[] startWeights,
        uint256[] endWeights
    );

    /// @dev Indicates that the swap fee is below the minimum allowable swap fee.
    error MinSwapFee();

    /// @dev Indicates that the swap fee is above the maximum allowable swap fee.
    error MaxSwapFee();

    constructor(
        NewPoolParams memory params,
        IVault vault,
        address owner,
        bool swapEnabledOnStart
    ) WeightedPool(params, vault) Ownable(owner) {
        InputHelpers.ensureInputLengthMatch(_NUM_TOKENS, params.numTokens);
        // WeightedPool validates `numTokens == normalizedWeights.length`
        // _startGradualWeightChange validates weights

        uint256 currentTime = block.timestamp;
        _startGradualWeightChange(
            uint56(currentTime),
            uint56(currentTime),
            params.normalizedWeights,
            params.normalizedWeights,
            true,
            swapEnabledOnStart
        );
    }

    function updateWeightsGradually(
        uint256 startTime,
        uint256 endTime,
        uint256[] memory endWeights
    ) external onlyOwner {
        InputHelpers.ensureInputLengthMatch(_NUM_TOKENS, endWeights.length);
        WeightValidation.validateTwoWeights(endWeights[0], endWeights[1]);

        // Ensure startTime >= now
        startTime = GradualValueChange.resolveStartTime(startTime, endTime);

        // Ensure time will not overflow in storage; only check end (startTime <= endTime)
        GradualValueChange.ensureNoTimeOverflow(endTime, _MAX_TIME);

        _startGradualWeightChange(uint56(startTime), uint56(endTime), _getNormalizedWeights(), endWeights, false, true);
    }

    /**
     * @dev Return start time, end time, and endWeights as an array.
     * Current weights should be retrieved via `getNormalizedWeights()`.
     */
    function getGradualWeightUpdateParams()
        external
        view
        returns (uint256 startTime, uint256 endTime, uint256[] memory endWeights)
    {
        PoolState memory poolState = _poolState;

        startTime = poolState.startTime;
        endTime = poolState.endTime;

        endWeights = new uint256[](_NUM_TOKENS);
        endWeights[0] = poolState.endWeight0;
        endWeights[1] = FixedPoint.ONE - poolState.endWeight0;
    }

    /**
     * @notice Set the swap fee percentage.
     * @dev This is a permissioned function. The swap fee must be within the bounds set by
     * MIN_SWAP_FEE_PERCENTAGE/MAX_SWAP_FEE_PERCENTAGE. Emits the SwapFeePercentageChanged event.
     */
    function setSwapFeePercentage(uint256 swapFeePercentage) public virtual onlyOwner {
        _setSwapFeePercentage(swapFeePercentage);
    }

    /**
     * @notice Return the current value of the swap fee percentage.
     */
    function getSwapFeePercentage() public view virtual returns (uint256) {
        return _swapFeePercentage;
    }

    /**
     * @notice Pause/unpause trading.
     */
    function setSwapEnabled(bool swapEnabled) external onlyOwner {
        _poolState.swapEnabled = !swapEnabled;
    }

    /**
     * @notice Return whether swaps are enabled or not for the given pool.
     */
    function getSwapEnabled() external view returns (bool) {
        return _getPoolSwapEnabledState();
    }

    /* =========================================
     * =========================================
     * ============HOOK FUNCTIONS===============
     * =========================================
     * =========================================
     */

    /**
     * @notice Check that the caller who initiated the add liquidity operation is the owner.
     * @param initiator The address (usually a router contract) that initiated a swap operation on the Vault
     */
    function onBeforeAddLiquidity(
        address initiator,
        address,
        AddLiquidityKind,
        uint256[] memory,
        uint256,
        uint256[] memory,
        bytes memory
    ) external view onlyVault returns (bool success) {
        // Check `initiator == owner` first to avoid calling `getSender()` on a potentially non-router contract/address
        success = (initiator == owner()) || (IRouterCommon(initiator).getSender() == owner());
    }

    /**
     * @notice Called before a swap to give the Pool block swap in paused pool.
     * @return success True if the pool is not paused.
     */
    function onBeforeSwap(PoolSwapParams calldata, address) public virtual onlyVault returns (bool) {
        return _getPoolSwapEnabledState();
    }

    /**
     * @notice Called after `onBeforeSwap` and before the main swap operation, if the pool has dynamic fees.
     * @return success True if the pool wishes to proceed with settlement
     * @return dynamicSwapFeePercentage Value of the swap fee percentage, as an 18-decimal FP value
     */
    function onComputeDynamicSwapFeePercentage(
        PoolSwapParams calldata,
        address,
        uint256
    ) external view onlyVault returns (bool, uint256) {
        return (true, getSwapFeePercentage());
    }

    /* =========================================
     * =========================================
     * ==========INTERNAL FUNCTIONS=============
     * =========================================
     * =========================================
     */

    function _getNormalizedWeight0() internal view virtual returns (uint256) {
        PoolState memory poolState = _poolState;
        uint256 pctProgress = _getWeightChangeProgress(poolState);
        return GradualValueChange.interpolateValue(poolState.startWeight0, poolState.endWeight0, pctProgress);
    }

    function _getNormalizedWeight(uint256 tokenIndex) internal view virtual override returns (uint256) {
        uint256 normalizedWeight0 = _getNormalizedWeight0();
        if (tokenIndex == 0) {
            return normalizedWeight0;
        } else if (tokenIndex == 1) {
            return FixedPoint.ONE - normalizedWeight0;
        }
        revert IVaultErrors.InvalidToken();
    }

    function _getNormalizedWeights() internal view override returns (uint256[] memory) {
        uint256[] memory normalizedWeights = new uint256[](_NUM_TOKENS);
        normalizedWeights[0] = _getNormalizedWeight0();
        normalizedWeights[1] = FixedPoint.ONE - normalizedWeights[0];
        return normalizedWeights;
    }

    function _getWeightChangeProgress(PoolState memory poolState) internal view returns (uint256) {
        return GradualValueChange.calculateValueChangeProgress(poolState.startTime, poolState.endTime);
    }

    /**
     * @dev When calling updateWeightsGradually again during an update, reset the start weights to the current weights,
     * if necessary.
     */
    function _startGradualWeightChange(
        uint56 startTime,
        uint56 endTime,
        uint256[] memory startWeights,
        uint256[] memory endWeights,
        bool modifySwapEnabledStatus,
        bool newSwapEnabled
    ) internal virtual {
        WeightValidation.validateTwoWeights(endWeights[0], endWeights[1]);

        PoolState memory poolState = _poolState;
        poolState.startTime = startTime;
        poolState.endTime = endTime;
        poolState.startWeight0 = uint64(startWeights[0]);
        poolState.endWeight0 = uint64(endWeights[0]);

        if (modifySwapEnabledStatus) {
            poolState.swapEnabled = newSwapEnabled;
            emit SwapEnabledSet(newSwapEnabled);
        }

        _poolState = poolState;
        emit GradualWeightUpdateScheduled(startTime, endTime, startWeights, endWeights);
    }

    function _setSwapFeePercentage(uint256 swapFeePercentage) internal virtual {
        // TODO: can we get min/max swap fee as internal fns in the WP base class? External call is wasteful.
        if (swapFeePercentage < this.getMinimumSwapFeePercentage()) {
            revert MinSwapFee();
        }
        // TODO: can we get min/max swap fee as internal fns in the WP base class? External call is wasteful.
        if (swapFeePercentage > this.getMaximumSwapFeePercentage()) {
            revert MaxSwapFee();
        }

        _swapFeePercentage = swapFeePercentage;
        emit SwapFeePercentageChanged(swapFeePercentage);
    }

    function _getPoolSwapEnabledState() internal view returns (bool) {
        return _poolState.swapEnabled;
    }
}
