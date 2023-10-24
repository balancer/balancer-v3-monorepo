// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/ITemporarilyPausable.sol";

/**
 * @dev Contract has a compatible interface with OpenZeppelin's Pauseable smart contract
 * https://docs.openzeppelin.com/contracts/4.x/api/security#Pausable
 * Inheritance is not used because OZ lib is using revert strings and we are using custom errors
 */
abstract contract TemporarilyPausable is ITemporarilyPausable {
    // The Pause Window and Buffer Period are timestamp-based: they should not be relied upon for sub-minute accuracy.
    // solhint-disable not-rely-on-time

    uint256 internal immutable _pauseWindowEndTime;
    uint256 internal immutable _bufferPeriodEndTime;

    bool private _paused;

    /**
     * @dev Initializes the contract with the given Pause Window and Buffer Period durations.
     * @param pauseWindowDuration Duration of the Pause Window in seconds
     * @param bufferPeriodDuration Duration of the Buffer Period in seconds
     */
    constructor(uint256 pauseWindowDuration, uint256 bufferPeriodDuration) {
        if (pauseWindowDuration > PausableConstants.MAX_PAUSE_WINDOW_DURATION) {
            revert PauseWindowDurationTooLarge();
        }
        if (bufferPeriodDuration > PausableConstants.MAX_BUFFER_PERIOD_DURATION) {
            revert BufferPeriodDurationTooLarge();
        }

        uint256 pauseWindowEndTime = block.timestamp + pauseWindowDuration;

        _pauseWindowEndTime = pauseWindowEndTime;
        _bufferPeriodEndTime = pauseWindowEndTime + bufferPeriodDuration;
    }

    /// @dev Modifier to make a function callable only when the contract is not paused.
    modifier whenNotPaused() {
        _requireNotPaused();
        _;
    }

    /// @dev Modifier to make a function callable only when the contract is paused.
    modifier whenPaused() {
        _requirePaused();
        _;
    }

    /**
     * @dev Sets the pause state to `paused`. The contract can only be paused until the end of the Pause Window, and
     * unpaused until the end of the Buffer Period.
     *
     * Once the Buffer Period expires, this function reverts unconditionally.
     */
    function _pause() internal whenNotPaused {
        if (block.timestamp >= _pauseWindowEndTime) {
            revert PauseWindowExpired();
        }
        _paused = true;
        emit Paused(msg.sender);
    }

    /// @dev Returns the contract to a normal (unpaused) state.
    function _unpause() internal whenPaused {
        _paused = false;
        emit Unpaused(msg.sender);
    }

    /// @inheritdoc ITemporarilyPausable
    function paused() public view override returns (bool) {
        return block.timestamp <= _bufferPeriodEndTime && _paused;
    }

    /// @inheritdoc ITemporarilyPausable
    function getPauseEndTimes() public view override returns (uint256 pauseWindowEndTime, uint256 bufferPeriodEndTime) {
        return (_pauseWindowEndTime, _bufferPeriodEndTime);
    }

    /// @dev Throws if the contract is paused.
    function _requireNotPaused() internal view {
        if (paused()) {
            revert AlreadyPaused();
        }
    }

    /// @dev Throws if the contract is not paused.
    function _requirePaused() internal view {
        if (!paused()) {
            revert AlreadyUnpaused();
        }
    }
}

/// @dev Keep the maximum durations in a single place.
library PausableConstants {
    uint256 public constant MAX_PAUSE_WINDOW_DURATION = 270 days;
    uint256 public constant MAX_BUFFER_PERIOD_DURATION = 90 days;
}
