// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

interface ITemporarilyPausable {
    /// @dev The caller specified a pause window period longer than the maximum.
    error PauseWindowDurationTooLarge();

    /// @dev The caller specified a buffer period longer than the maximum.
    error BufferPeriodDurationTooLarge();

    /**
     * @notice Retrieve the stored pause configuration (pause window and buffer durations).
     * @return pauseWindowDuration The length of the pause window (seconds)
     * @return bufferPeriodDuration The length of the buffer period (seconds)
     */
    function getPauseConfiguration() external view returns (uint256 pauseWindowDuration, uint256 bufferPeriodDuration);
}

/// @dev Keep the maximum durations in a single place.
library PausableConstants {
    uint256 public constant MAX_PAUSE_WINDOW_DURATION = 365 days * 3;
    uint256 public constant MAX_BUFFER_PERIOD_DURATION = 90 days;
}
