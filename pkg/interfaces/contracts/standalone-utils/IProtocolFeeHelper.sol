// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

/**
 * @notice Maintain a set of pools whose protocol fees can be set from this helper contract, vs. the fee controller.
 * @dev Governance can add a set of pools to this contract, then grant permission to call protocol swap- or yield-
 * setting functions here, which allows greater granularity than setting permissions directly on the fee controller.
 *
 * Note that governance must grant this contract permission to call the pool protocol fee setting functions on the
 * controller.
 */
interface IProtocolFeeHelper {
    /***************************************************************************
                                    Manage Pools
    ***************************************************************************/

    /**
     * @notice Set the protocol swap fee for a pool.
     * @dev This contract must be granted permission to set swap and yield protocol fees, but governance can
     * independently grant permission to call the swap and yield fee setters.
     *
     * @param pool The address of the pool
     * @param newProtocolSwapFeePercentage The new protocol swap fee percentage
     */
    function setProtocolSwapFeePercentage(address pool, uint256 newProtocolSwapFeePercentage) external;

    /**
     * @notice Set the protocol yield fee for a pool.
     * @dev This contract must be granted permission to set swap and yield protocol fees, but governance can
     * independently grant permission to call the swap and yield fee setters.
     *
     * @param pool The address of the pool
     * @param newProtocolYieldFeePercentage The new protocol yield fee percentage
     */
    function setProtocolYieldFeePercentage(address pool, uint256 newProtocolYieldFeePercentage) external;
}
