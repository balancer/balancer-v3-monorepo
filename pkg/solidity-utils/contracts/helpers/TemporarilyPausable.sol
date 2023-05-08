// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.18;

import "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/ITemporarilyPausable.sol";

/**
 * @dev Allows for a contract to be paused during an initial period after deployment, disabling functionality. Can be
 * used as an emergency switch in case a security vulnerability or threat is identified.
 *
 * The contract can only be paused during the Pause Window, a period that starts at deployment. It can also be
 * unpaused and re-paused any number of times during this period. This is intended to serve as a safety measure: it lets
 * system managers react quickly to potentially dangerous situations, knowing that this action is reversible if careful
 * analysis later determines there was a false alarm.
 *
 * If the contract is paused when the Pause Window finishes, it will remain in the paused state through an additional
 * Buffer Period, after which it will be automatically unpaused forever. This is to ensure there is always enough time
 * to react to an emergency, even if the threat is discovered shortly before the Pause Window expires.
 *
 * Note that since the contract can only be paused within the Pause Window, unpausing during the Buffer Period is
 * irreversible.
 *
 * Contract has a compatible inteface with OpenZeppelin Pauseable smart contract
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
     * @param pauseWindowDuration Duration of the Pause Window in seconds.
     * @param bufferPeriodDuration Duration of the Buffer Period in seconds.
     */
    constructor(uint256 pauseWindowDuration, uint256 bufferPeriodDuration) {
        if (pauseWindowDuration > PausableConstants.MAX_PAUSE_WINDOW_DURATION) {
            revert MaxPauseWindowDuration();
        }
        if (bufferPeriodDuration > PausableConstants.MAX_BUFFER_PERIOD_DURATION) {
            revert MaxBufferPeriodDuration();
        }

        uint256 pauseWindowEndTime = block.timestamp + pauseWindowDuration;

        _pauseWindowEndTime = pauseWindowEndTime;
        _bufferPeriodEndTime = pauseWindowEndTime + bufferPeriodDuration;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is not paused.
     */
    modifier whenNotPaused() {
        _requireNotPaused();
        _;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is paused.
     */
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

    /**
     * @dev Returns the contract to a normal (unpaused) state.
     */
    function _unpause() internal whenPaused {
        if (block.timestamp >= _bufferPeriodEndTime) {
            revert BufferPeriodExpired();
        }
        _paused = false;
        emit Unpaused(msg.sender);
    }

    /**
     * @dev Returns true if the contract is paused, and false otherwise.
     *
     * Once the Buffer Period expires, the gas cost of calling this function is reduced dramatically, as storage is no
     * longer accessed.
     */
    function paused() public view returns (bool) {
        return block.timestamp <= _bufferPeriodEndTime && _paused;
    }

    /**
     * @dev Throws if the contract is paused.
     */
    function _requireNotPaused() internal view {
        if (paused()) {
            revert AlreadyPaused();
        }
    }

    /**
     * @dev Throws if the contract is not paused.
     */
    function _requirePaused() internal view {
        if (!paused()) {
            revert AlreadyUnPaused();
        }
    }
}

/**
 * @dev Keep the maximum durations in a single place.
 */
library PausableConstants {
    uint256 public constant MAX_PAUSE_WINDOW_DURATION = 270 days;
    uint256 public constant MAX_BUFFER_PERIOD_DURATION = 90 days;
}
