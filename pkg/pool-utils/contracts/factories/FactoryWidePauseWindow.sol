// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "@balancer-labs/v3-interfaces/contracts/vault/ITemporarilyPausable.sol";

/**
 * @dev Utility to create Pool factories for Pools that use the `TemporarilyPausable` contract.
 *
 * By calling `TemporarilyPausable`'s constructor with the result of `getPauseConfiguration`, all Pools created by this
 * factory will share the same Pause Window end time, after which both old and new Pools will not be pausable.
 */
contract FactoryWidePauseWindow is ITemporarilyPausable {
    // This contract relies on timestamps in a similar way as `TemporarilyPausable` does - the same caveats apply.
    // solhint-disable not-rely-on-time

    uint256 private immutable _initialPauseWindowDuration;
    uint256 private immutable _bufferPeriodDuration;

    // Time when the pause window for all created Pools expires, and the pause window duration of new Pools becomes
    // zero.
    uint256 private immutable _poolsPauseWindowEndTime;

    constructor(uint256 initialPauseWindowDuration, uint256 bufferPeriodDuration) {
        // New pools will check on deployment that the durations given are within the bounds specified by
        // `TemporarilyPausable`. Since it is now possible for a factory to pass in arbitrary values here,
        // pre-emptively verify that these durations are valid for pool creation.
        // (Otherwise, you would be able to deploy a useless factory where `create` would always revert.)

        if (initialPauseWindowDuration > PausableConstants.MAX_PAUSE_WINDOW_DURATION) {
            revert PauseWindowDurationTooLarge();
        }

        if (bufferPeriodDuration > PausableConstants.MAX_BUFFER_PERIOD_DURATION) {
            revert BufferPeriodDurationTooLarge();
        }

        _initialPauseWindowDuration = initialPauseWindowDuration;
        _bufferPeriodDuration = bufferPeriodDuration;

        _poolsPauseWindowEndTime = block.timestamp + initialPauseWindowDuration;
    }

    /**
     * @dev Returns the current `TemporarilyPausable` configuration that will be applied to Pools created by this
     * factory.
     *
     * `pauseWindowDuration` will decrease over time until it reaches zero, at which point both it and
     * `bufferPeriodDuration` will be zero forever, meaning deployed Pools will not be pausable.
     */
    function getPauseConfiguration() public view returns (uint256 pauseWindowDuration, uint256 bufferPeriodDuration) {
        uint256 currentTime = block.timestamp;
        if (currentTime < _poolsPauseWindowEndTime) {
            // The buffer period is always the same since its duration is related to how much time is needed to respond
            // to a potential emergency. The Pause Window duration however decreases as the end time approaches.

            pauseWindowDuration = _poolsPauseWindowEndTime - currentTime; // No need for checked arithmetic.
            bufferPeriodDuration = _bufferPeriodDuration;
        } else {
            // After the end time, newly created Pools have no Pause Window, nor Buffer Period (since they are not
            // pausable in the first place).

            pauseWindowDuration = 0;
            bufferPeriodDuration = 0;
        }
    }
}
