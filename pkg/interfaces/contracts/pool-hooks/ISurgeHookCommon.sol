// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { PoolSwapParams } from "../vault/VaultTypes.sol";

interface ISurgeHookCommon {
    /// @notice The max surge fee and threshold values must be valid percentages.
    error InvalidPercentage();

    // Percentages are 18-decimal FP values, which fit in 64 bits (sized ensure a single slot).
    struct SurgeFeeData {
        uint64 thresholdPercentage;
        uint64 maxSurgeFeePercentage;
    }

    /**
     * @notice The threshold percentage has been changed for a pool in a `ECLPSurgeHook` contract.
     * @dev Note, the initial threshold percentage is set on deployment, and an event is emitted.
     * @param pool The pool for which the threshold percentage has been changed
     * @param newSurgeThresholdPercentage The new threshold percentage
     */
    event ThresholdSurgePercentageChanged(address indexed pool, uint256 newSurgeThresholdPercentage);

    /**
     * @notice The maximum surge fee percentage has been changed for a pool in a `ECLPSurgeHook` contract.
     * @dev Note, the initial max surge fee percentage is set on deployment, and an event is emitted.
     * @param pool The pool for which the max surge fee percentage has been changed
     * @param newMaxSurgeFeePercentage The new max surge fee percentage
     */
    event MaxSurgeFeePercentageChanged(address indexed pool, uint256 newMaxSurgeFeePercentage);

    /**
     * @notice Getter for the default maximum surge surge fee percentage.
     * @return maxSurgeFeePercentage The default max surge fee percentage for this hook contract
     */
    function getDefaultMaxSurgeFeePercentage() external view returns (uint256);

    /**
     * @notice Getter for the default surge threshold percentage.
     * @return surgeThresholdPercentage The default surge threshold percentage for this hook contract
     */
    function getDefaultSurgeThresholdPercentage() external view returns (uint256);

    /**
     * @notice Getter for the maximum surge fee percentage for a pool.
     * @param pool The pool for which the max surge fee percentage is requested
     * @return maxSurgeFeePercentage The max surge fee percentage for the pool
     */
    function getMaxSurgeFeePercentage(address pool) external view returns (uint256);

    /**
     * @notice Getter for the surge threshold percentage for a pool.
     * @param pool The pool for which the surge threshold percentage is requested
     * @return surgeThresholdPercentage The surge threshold percentage for the pool
     */
    function getSurgeThresholdPercentage(address pool) external view returns (uint256);

    /**
     * @notice Sets the max surge fee percentage.
     * @dev This function must be permissioned. If the pool does not have a swap fee manager role set, the max surge
     * fee can only be changed by governance. It is initially set to the default max surge fee for this hook contract.
     */
    function setMaxSurgeFeePercentage(address pool, uint256 newMaxSurgeSurgeFeePercentage) external;

    /**
     * @notice Sets the hook threshold percentage.
     * @dev This function must be permissioned. If the pool does not have a swap fee manager role set, the surge
     * threshold can only be changed by governance. It is initially set to the default threshold for this hook contract.
     */
    function setSurgeThresholdPercentage(address pool, uint256 newSurgeThresholdPercentage) external;

    /**
     * @notice Compute the surge fee percentage for a swap.
     * @dev If below threshold, return the standard static swap fee percentage. It is public to allow it to be called
     * off-chain.
     *
     * @param params Input parameters for the swap (balances needed)
     * @param pool The pool we are computing the fee for
     * @param staticSwapFeePercentage The static fee percentage for the pool (default if there is no surge)
     * @return surgeFeePercentage The surge fee percentage to be charged in the swap
     */
    function computeSwapSurgeFeePercentage(
        PoolSwapParams calldata params,
        address pool,
        uint256 staticSwapFeePercentage
    ) external view returns (uint256 surgeFeePercentage);

    /**
     * @notice Compute whether a swap will surge.
     * @dev If max surge fee is less than static fee, return false.
     * @param params Input parameters for the swap (balances needed)
     * @param pool The pool we are computing the surge flag for
     * @param staticSwapFeePercentage The static fee percentage for the pool (default if there is no surge)
     * @return isSurging True if the swap will surge, false otherwise
     */
    function isSurgingSwap(
        PoolSwapParams calldata params,
        address pool,
        uint256 staticSwapFeePercentage
    ) external view returns (bool isSurging);
}

// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { PoolSwapParams } from "../vault/VaultTypes.sol";

<<<<<<<< HEAD:pkg/interfaces/contracts/pool-hooks/IECLPSurgeHook.sol
interface IECLPSurgeHook {
    struct ImbalanceSlopeData {
        uint128 imbalanceSlopeBelowPeak;
        uint128 imbalanceSlopeAbovePeak;
    }

    /// @notice Thrown when an invalid imbalance slope is provided.
    error InvalidImbalanceSlope();

    /**
     * @notice A new `ECLPSurgeHook` contract has been registered successfully.
     * @dev If the registration fails the call will revert, so there will be no event.
     * @param pool The pool on which the hook was registered
     * @param factory The factory that registered the pool
     */
    event ECLPSurgeHookRegistered(address indexed pool, address indexed factory);
========
interface ISurgeHookCommon {
    /// @notice The max surge fee and threshold values must be valid percentages.
    error InvalidPercentage();

    // Percentages are 18-decimal FP values, which fit in 64 bits (sized ensure a single slot).
    struct SurgeFeeData {
        uint64 thresholdPercentage;
        uint64 maxSurgeFeePercentage;
    }
>>>>>>>> main:pkg/interfaces/contracts/pool-hooks/ISurgeHookCommon.sol

    /**
     * @notice The imbalance slope below peak has been changed for a pool in a `ECLPSurgeHook` contract.
     * @dev Note, the initial imbalance slope below peak is set on deployment, and an event is emitted.
     * @param pool The pool for which the imbalance slope below peak has been changed
     * @param newImbalanceSlopeBelowPeak The new imbalance slope below peak
     */
    event ImbalanceSlopeBelowPeakChanged(address indexed pool, uint128 newImbalanceSlopeBelowPeak);

    /**
     * @notice The imbalance slope above peak has been changed for a pool in a `ECLPSurgeHook` contract.
     * @dev Note, the initial imbalance slope above peak is set on deployment, and an event is emitted.
     * @param pool The pool for which the imbalance slope above peak has been changed
     * @param newImbalanceSlopeAbovePeak The new imbalance slope above peak
     */
<<<<<<<< HEAD:pkg/interfaces/contracts/pool-hooks/IECLPSurgeHook.sol
    event ImbalanceSlopeAbovePeakChanged(address indexed pool, uint128 newImbalanceSlopeAbovePeak);
========
    event MaxSurgeFeePercentageChanged(address indexed pool, uint256 newMaxSurgeFeePercentage);
>>>>>>>> main:pkg/interfaces/contracts/pool-hooks/ISurgeHookCommon.sol

    /**
     * @notice Getter for the imbalance slope below peak for a pool.
     * @param pool The pool for which the imbalance slope below peak is requested
     * @return imbalanceSlopeBelowPeak The imbalance slope below peak for the pool
     */
    function getImbalanceSlopeBelowPeak(address pool) external view returns (uint128);

    /**
     * @notice Getter for the imbalance slope above peak for a pool.
     * @param pool The pool for which the imbalance slope above peak is requested
     * @return imbalanceSlopeAbovePeak The imbalance slope above peak for the pool
     */
    function getImbalanceSlopeAbovePeak(address pool) external view returns (uint128);

    /**
     * @notice Sets the imbalance slope below peak for a pool.
     * @dev This function must be permissioned. If the pool does not have a swap fee manager role set, the imbalance
     * slope below peak can only be changed by governance. It is initially set to the default imbalance slope for this
     * hook contract.
     *
     * @param pool The pool for which the imbalance slope below peak is being set
     * @param newImbalanceSlopeBelowPeak The new imbalance slope below peak
     */
    function setImbalanceSlopeBelowPeak(address pool, uint128 newImbalanceSlopeBelowPeak) external;

    /**
     * @notice Sets the imbalance slope above peak for a pool.
     * @dev This function must be permissioned. If the pool does not have a swap fee manager role set, the imbalance
     * slope above peak can only be changed by governance. It is initially set to the default imbalance slope for this
     * hook contract.
     *
     * @param pool The pool for which the imbalance slope above peak is being set
     * @param newImbalanceSlopeAbovePeak The new imbalance slope above peak
     */
    function setImbalanceSlopeAbovePeak(address pool, uint128 newImbalanceSlopeAbovePeak) external;
}
