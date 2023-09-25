// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

/**
 * @title ITemporarilyPausable
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
 */
interface ITemporarilyPausable {
    /**
     * @dev Error indicating that the maximum pause window duration has been exceeded.
     */
    error PauseWindowDurationTooLarge();

    /**
     * @dev Error indicating that the maximum buffer period duration has been exceeded.
     */
    error BufferPeriodDurationTooLarge();

    /**
     * @dev Error indicating that the pause window has expired.
     */
    error PauseWindowExpired();

    /**
     * @dev Error indicating that the buffer period has expired.
     */
    error BufferPeriodExpired();

    /**
     * @dev Error indicating that the contract is already paused.
     */
    error AlreadyPaused();

    /**
     * @dev Error indicating that the contract is already unpaused.
     */
    error AlreadyUnpaused();

    /**
     * @dev Returns true if the contract is paused, and false otherwise.
     *
     * Once the Buffer Period expires, the gas cost of calling this function is reduced dramatically, as storage is no
     * longer accessed.
     */
    function paused() external view returns (bool);

    /**
     * @dev Returns the end times of the pause window and buffer period.
     */
    function getPauseEndTimes() external view returns (uint256 pauseWindowEndTime, uint256 bufferPeriodEndTime);

    /**
     * @dev Emitted when the pause is triggered by `account`.
     * @param account The address that triggered the pause event.
     */
    event Paused(address indexed account);

    /**
     * @dev Emitted when the pause is lifted by `account`.
     * @param account The address that triggered the unpause event.
     */
    event Unpaused(address indexed account);
}
