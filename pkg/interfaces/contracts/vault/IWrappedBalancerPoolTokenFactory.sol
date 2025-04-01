// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

/// @notice Interface for factory contract for creating wrapped Balancer pool tokens
interface IWrappedBalancerPoolTokenFactory {
    /// @notice The wrapped BPT already exists
    error WrappedBPTAlreadyExists(address wrappedToken);

    /// @notice The factory is paused
    error FactoryPaused();

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

    /**
     * @notice Sets the factory to be disabled or enabled
     * @param disabled True to disable the factory, false to enable it
     */
    function setDisabled(bool disabled) external;

    /**
     * @notice Checks if the factory is disabled
     * @return bool True if the factory is disabled, false if it is enabled
     */
    function isDisabled() external view returns (bool);
}
