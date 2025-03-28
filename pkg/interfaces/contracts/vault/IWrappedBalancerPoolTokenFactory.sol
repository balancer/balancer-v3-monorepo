// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

/// @notice Interface for factory contract for creating wrapped Balancer pool tokens
interface IWrappedBalancerPoolTokenFactory {
    /// @notice The wrapped BPT already exists
    error WrappedBPTAlreadyExists(address wrappedToken);

    /// @notice The Balancer pool token has not been initialized
    error BalancerPoolTokenNotInitialized();

    /// @notice Wrapped Token was created
    event WrappedTokenCreated(address indexed balancerPoolToken, address wrappedToken);

    /**
     * @notice Creates a wrapped token for the given Balancer pool token
     * @param balancerPoolToken The Balancer pool token to wrap
     * @return address The wrapped token address
     */
    function createWrappedToken(address balancerPoolToken) external returns (address);

    /**
     * @notice Gets the wrapped token for the given Balancer pool token
     * @param balancerPoolToken The Balancer pool token
     * @return address The wrapped token address
     */
    function getWrappedToken(address balancerPoolToken) external view returns (address);
}
