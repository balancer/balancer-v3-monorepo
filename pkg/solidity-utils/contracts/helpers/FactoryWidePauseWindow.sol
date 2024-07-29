// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

/**
 * @notice Base contract for v3 factories to support pause windows for pools based on the factory deployment time.
 * @dev Each pool deployment calls `getPauseWindowDuration` on the factory so that all Pools created by this factory
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

    /// @dev The factory deployer gave a duration that would overflow the Unix timestamp.
    error PoolPauseWindowDurationOverflow();

    // The pause window end time is stored in 32 bits.
    uint32 private constant _MAX_TIMESTAMP = type(uint32).max;

    uint32 private immutable _pauseWindowDuration;

    // Time when the pause window for all created Pools expires.
    uint32 private immutable _poolsPauseWindowEndTime;

    constructor(uint32 pauseWindowDuration) {
        if (block.timestamp + pauseWindowDuration > _MAX_TIMESTAMP) {
            revert PoolPauseWindowDurationOverflow();
        }

        _pauseWindowDuration = pauseWindowDuration;

        _poolsPauseWindowEndTime = uint32(block.timestamp) + pauseWindowDuration;
    }

    /**
     * @notice Return the pause window duration. This is the time pools will be pausable after factory deployment.
     * @return The duration in seconds
     */
    function getPauseWindowDuration() external view returns (uint32) {
        return _pauseWindowDuration;
    }

    /**
     * @notice Returns the original factory pauseWindowEndTime, regardless of the current time.
     * @return The end time as a timestamp
     */
    function getOriginalPauseWindowEndTime() external view returns (uint32) {
        return _poolsPauseWindowEndTime;
    }

    /**
     * @notice Returns the current pauseWindowEndTime that will be applied to Pools created by this factory.
     * @dev We intend for all pools deployed by this factory to have the same pause window end time (i.e., after
     * this date, all future pools will be unpausable). This function will return `_poolsPauseWindowEndTime`
     * until it passes, after which it will return 0.
     *
     * @return The resolved pause window end time (0 indicating it's no longer pausable)
     */
    function getNewPoolPauseWindowEndTime() public view returns (uint32) {
        return uint32(block.timestamp) < _poolsPauseWindowEndTime ? _poolsPauseWindowEndTime : 0;
    }
}
