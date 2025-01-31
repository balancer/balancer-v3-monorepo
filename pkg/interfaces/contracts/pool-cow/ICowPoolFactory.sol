// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { PoolRoleAccounts, TokenConfig } from "../vault/VaultTypes.sol";

interface ICowPoolFactory {
    /// @notice The trusted CoW router cannot be neither address zero nor the address of the factory.
    error InvalidTrustedCowRouter(address invalidTrustedCowRouter);

    /// @notice Trusted CoW Router has changed.
    event CowTrustedRouterChanged(address newTrustedCowRouter);

    /**
     * @notice Deploys a new `CowPool`.
     * @dev Tokens must be sorted for pool registration.
     * @param name The name of the pool
     * @param symbol The symbol of the pool
     * @param tokens An array of descriptors for the tokens the pool will manage
     * @param normalizedWeights The pool weights (must add to FixedPoint.ONE)
     * @param roleAccounts Addresses the Vault will allow to change certain pool settings
     * @param swapFeePercentage Initial swap fee percentage
     * @param salt The salt value that will be passed to create2 deployment
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
     * @return trustedCowRouter Address of trusted CoW AMM Router.
     */
    function getTrustedCowRouter() external view returns (address trustedCowRouter);

    /**
     * @notice Sets the current trusted CoW Router in the factory.
     * @dev This permissioned function checks if the new trusted router's address is not zero or the address of the
     * factory, which are not valid addresses.
     *
     * @param newTrustedCowRouter Address of new trusted CoW AMM Router.
     */
    function setTrustedCowRouter(address newTrustedCowRouter) external;
}
