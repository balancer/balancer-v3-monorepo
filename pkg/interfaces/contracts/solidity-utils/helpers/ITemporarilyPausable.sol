// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

/**
 * @title ITemporarilyPausable
 * @dev Interface for contracts that need temporarily pausable functionality.
 * This interface defines error types and events related to pausing and unpausing a contract.
 */
interface ITemporarilyPausable {
    /**
     * @dev Error indicating that the maximum pause window duration has been exceeded.
     */
    error MaxPauseWindowDuration();

    /**
     * @dev Error indicating that the maximum buffer period duration has been exceeded.
     */
    error MaxBufferPeriodDuration();

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
    error AlreadyUnPaused();

    /**
     * @dev Returns true if the contract is paused, and false otherwise.
     *
     * Once the Buffer Period expires, the gas cost of calling this function is reduced dramatically, as storage is no
     * longer accessed.
     */
    function paused() external view returns (bool);

    /**
     * @dev Emitted when the pause is triggered by `account`.
     * @param account The address that triggered the pause event.
     */
    event Paused(address account);

    /**
     * @dev Emitted when the pause is lifted by `account`.
     * @param account The address that triggered the unpause event.
     */
    event Unpaused(address account);
}
