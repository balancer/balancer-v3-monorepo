// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { PoolRoleAccounts, TokenConfig } from "../vault/VaultTypes.sol";

interface ICowPoolFactory {
    /**
     * @notice The address of the trusted CoW Router has changed.
     * @param newTrustedCowRouter The current trusted CoW Router address
     */
    event CowTrustedRouterChanged(address newTrustedCowRouter);

    /// @notice The trusted CoW router cannot be address zero.
    error InvalidTrustedCowRouter();

    /**
     * @notice Deploys a new `CowPool`.
     * @dev Tokens must be sorted for pool registration.
     * @param name The name of the pool
     * @param symbol The symbol of the pool
     * @param tokens An array of descriptors for the tokens the pool will manage
     * @param normalizedWeights The pool weights (must sum to FixedPoint.ONE)
     * @param roleAccounts Addresses the Vault will allow to change certain pool settings
     * @param swapFeePercentage Initial swap fee percentage
     * @param salt The salt value that will be passed to deployment
     */
    function create(
        string memory name,
        string memory symbol,
        TokenConfig[] memory tokens,
        uint256[] memory normalizedWeights,
        PoolRoleAccounts memory roleAccounts,
        uint256 swapFeePercentage,
        bytes32 salt
    ) external returns (address pool);

    /**
     * @notice Gets the current trusted CoW Router in the factory.
     * @return trustedCowRouter Address of the trusted CoW AMM Router.
     */
    function getTrustedCowRouter() external view returns (address trustedCowRouter);

    /**
     * @notice Sets the current trusted CoW Router in the factory.
     * @dev This permissioned function ensures that the new trusted router address is non-zero.
     *
     * @param newTrustedCowRouter Address of new trusted CoW AMM Router.
     */
    function setTrustedCowRouter(address newTrustedCowRouter) external;
}
