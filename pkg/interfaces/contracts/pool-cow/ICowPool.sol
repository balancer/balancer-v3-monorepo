// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

interface ICowPool {
    /// @notice Trusted CoW Router has been refreshed with trusted router from the pool factory.
    event CowTrustedRouterRefreshed(address newTrustedCowRouter);

    /**
     * @notice Returns the trusted router address.
     * @dev The CoW Router address is registered in the factory. To minimize external calls from the pool to the
     * factory, the trusted router address is cached within the pool. This variable has no setter; therefore, updating
     * it requires calling `refreshTrustedCowRouter()`.
     * @return cowRouter The address of the trusted CoW Router
     */
    function getTrustedCowRouter() external view returns (address cowRouter);

    /**
     * @notice Updates the trusted router value according to the CoW AMM Factory.
     */
    function refreshTrustedCowRouter() external;
}
