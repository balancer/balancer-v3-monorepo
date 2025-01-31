// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

interface ICowPool {
    /// @notice Trusted CoW Router has been refreshed with trusted router from the pool factory.
    event CowTrustedRouterRefreshed(address newTrustedCowRouter);

    /**
     * @notice Updates the trusted router value according to the CoW AMM Factory.
     */
    function refreshTrustedCowRouter() external;
}
