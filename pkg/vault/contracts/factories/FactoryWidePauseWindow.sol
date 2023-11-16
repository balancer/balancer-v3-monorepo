// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

/**
 * @dev Base contract for V3 factories to support pause windows for pools based on the factory deployment time.
 * Each pool deployment calls `getPauseWindowDuration` on the factory so that all Pools created by this factory
 * will share the same Pause Window end time, after which both old and new Pools will not be pausable.
 *
 * All pools are reversibly pausable until the pause window expires. Afterward, there is an additional buffer
 * period, set to the same duration as the Vault's buffer period. If a pool was paused, it will remain paused
 * through this buffer period, and cannot be unpaused.
 *
 * When the buffer period expires, it will unpause automatically, and remain permissionless forever after.
 */
contract FactoryWidePauseWindow {
    // This contract relies on timestamps - the usual caveats apply.
    // solhint-disable not-rely-on-time

    uint256 private immutable _initialPauseWindowDuration;

    // Time when the pause window for all created Pools expires, and the pause window duration of new Pools
    // becomes zero.
    uint256 private immutable _poolsPauseWindowEndTime;

    constructor(uint256 initialPauseWindowDuration) {
        _initialPauseWindowDuration = initialPauseWindowDuration;

        _poolsPauseWindowEndTime = block.timestamp + initialPauseWindowDuration;
    }

    /**
     * @dev Returns the current pauseWindowDuration that will be applied to Pools created by this factory.
     *
     * `pauseWindowDuration` will decrease over time until it reaches zero, at which point any pools created are
     * permissionless forever.
     */
    function getPauseWindowDuration() public view returns (uint256 pauseWindowDuration) {
        uint256 currentTime = block.timestamp;

        if (currentTime < _poolsPauseWindowEndTime) {
            // The Pause Window duration decreases as the end time approaches.

            unchecked {
                pauseWindowDuration = _poolsPauseWindowEndTime - currentTime; // No need for checked arithmetic.
            }
        } else {
            // After the end time, newly created Pools have no Pause Window, since they are no longer pausable.

            pauseWindowDuration = 0;
        }
    }
}
