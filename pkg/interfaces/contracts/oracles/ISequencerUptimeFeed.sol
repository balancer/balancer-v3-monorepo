// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @notice Interface to the LP oracle's sequencer uptime feed, used by L2s to indicate the L1 synchronization status.
 * @dev Optimistic rollups (e.g., Arbitrum, Optimism) and many ZK-rollups rely on sequencers to efficiently manage
 * transaction ordering, execution, and batching before submitting them to Layer 1. If this sequencer goes down,
 * L2 applications will not be updated in a timely fashion, which is particularly important for price oracles. To
 * mitigate this risk, Chainlink provides a sequencer uptime feed to track the status of the sequencer, including
 * the time since the last restart (see https://docs.chain.link/data-feeds/l2-sequencer-feeds).
 */
interface ISequencerUptimeFeed {
    /// @notice The uptime sequencer has returned a status of "down".
    error SequencerDown();

    /**
     * @notice A price feed was accessed while still within the resync window (e.g., after a sequencer outage).
     * @dev Since outages result in a queue of delayed transactions which must be processed, the stabilization period
     * (or resync window) allows sufficient time for the L2 network to "catch up," so that the price feed is accurate.
     */
    error SequencerResyncIncomplete();

    /**
     * @notice Return the address of the sequencer uptime feed.
     * @dev This only applies to L2 networks that provide this feed to check on the status of the sequencer.
     * @return sequencerUptimeFeed The address of the feed contract (or zero if L1 or unsupported)
     */
    function getSequencerUptimeFeed() external view returns (AggregatorV3Interface sequencerUptimeFeed);

    /**
     * @notice Return the length of the sequencer uptime resync window.
     * @dev After an outage, the sequencer requires some time to "catch up" and ensure the L2 state matches L1.
     * @return uptimeResyncWindow The length of the uptime resync window, in seconds
     */
    function getUptimeResyncWindow() external view returns (uint256 uptimeResyncWindow);
}
