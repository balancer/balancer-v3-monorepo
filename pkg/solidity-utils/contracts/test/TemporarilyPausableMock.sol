// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.18;

import "../helpers/TemporarilyPausable.sol";

contract TemporarilyPausableMock is TemporarilyPausable {
    constructor(uint256 pauseWindowDuration, uint256 bufferPeriodDuration)
        TemporarilyPausable(pauseWindowDuration, bufferPeriodDuration)
    {}

    function unpause() external {
        _unpause();
    }

    function pause() external {
        _pause();
    }

    function getMaxPauseWindowDuration() external pure returns (uint256) {
        return PausableConstants.MAX_PAUSE_WINDOW_DURATION;
    }

    function getMaxBufferPeriodDuration() external pure returns (uint256) {
        return PausableConstants.MAX_BUFFER_PERIOD_DURATION;
    }
}
