// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IVault } from "./IVault.sol";

/// @notice Factory contract interface for creating wrapped Balancer pool tokens.
interface IWrappedBalancerPoolTokenFactory {
    /**
     * @notice BPT can only be wrapped once, and cannot be overwritten.
     * @param wrappedToken The existing wrapped token corresponding to the BPT
     */
    error WrappedBPTAlreadyExists(address wrappedToken);

    /// @notice The Balancer pool token has not been registered.
    error BalancerPoolTokenNotRegistered();

    /**
     * @notice A new wrapped token was created.
     * @param balancerPoolToken The original BPT
     * @param wrappedToken The wrapped version of the BPT
     */
    event WrappedTokenCreated(address indexed balancerPoolToken, address indexed wrappedToken);

    /**
     * @notice Get the address of the Balancer Vault.
     * @dev This contract uses the Vault to verify that the token being wrapped is a valid Balancer pool, and that it
     * has been initialized.
     *
     * @return vault Address of the Vault
     */
    function getVault() external view returns (IVault);

    /**
     * @notice Creates a wrapped token for the given Balancer pool token.
     * @dev Reverts if a wrapper has already been created for the BPT, or if the pool has not been initialized.
     * @param balancerPoolToken The Balancer pool token to wrap
     * @return address The wrapped token address
     */
    function createWrappedToken(address balancerPoolToken) external returns (address);

    /**
     * @notice Gets the wrapped token for the given Balancer pool token.
     * @param balancerPoolToken The Balancer pool token
     * @return wrappedToken The wrapped token address (or zero, if no wrapper has been created)
     */
    function getWrappedToken(address balancerPoolToken) external view returns (address);
}
