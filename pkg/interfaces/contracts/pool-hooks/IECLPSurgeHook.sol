// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

interface IECLPSurgeHook {
    /// @notice Thrown when an invalid imbalance slope is provided.
    error InvalidImbalanceSlope();

    /**
     * @notice The rotation angle is too small or too large for the surge hook to be used.
     * @dev The surge hook accepts angles from 30 to 60 degrees. Outside of this range, the computation of the peak
     * price cannot be approximated by sine/cosine.
     */
    error InvalidRotationAngle();

    /**
     * @notice A new `ECLPSurgeHook` contract has been registered successfully.
     * @dev If the registration fails the call will revert, so there will be no event.
     * @param pool The pool on which the hook was registered
     * @param factory The factory that registered the pool
     */
    event ECLPSurgeHookRegistered(address indexed pool, address indexed factory);

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
    event ImbalanceSlopeAbovePeakChanged(address indexed pool, uint128 newImbalanceSlopeAbovePeak);

    /**
     * @notice Getter for the imbalance slope below peak for a pool.
     * @param pool The pool for which the imbalance slope below peak is requested
     * @return imbalanceSlopeBelowPeak The imbalance slope below peak for the pool
     * @return imbalanceSlopeAbovePeak The imbalance slope above peak for the pool
     */
    function getImbalanceSlopes(
        address pool
    ) external view returns (uint256 imbalanceSlopeBelowPeak, uint256 imbalanceSlopeAbovePeak);

    /**
     * @notice Sets the imbalance slope below peak for a pool.
     * @dev This function must be permissioned. If the pool does not have a swap fee manager role set, the imbalance
     * slope below peak can only be changed by governance. It is initially set to the default imbalance slope for this
     * hook contract.
     *
     * @param pool The pool for which the imbalance slope below peak is being set
     * @param newImbalanceSlopeBelowPeak The new imbalance slope below peak
     */
    function setImbalanceSlopeBelowPeak(address pool, uint256 newImbalanceSlopeBelowPeak) external;

    /**
     * @notice Sets the imbalance slope above peak for a pool.
     * @dev This function must be permissioned. If the pool does not have a swap fee manager role set, the imbalance
     * slope above peak can only be changed by governance. It is initially set to the default imbalance slope for this
     * hook contract.
     *
     * @param pool The pool for which the imbalance slope above peak is being set
     * @param newImbalanceSlopeAbovePeak The new imbalance slope above peak
     */
    function setImbalanceSlopeAbovePeak(address pool, uint256 newImbalanceSlopeAbovePeak) external;
}
