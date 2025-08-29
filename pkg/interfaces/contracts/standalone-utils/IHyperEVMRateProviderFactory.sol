// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IHyperEVMRateProvider } from "./IHyperEVMRateProvider.sol";

interface IHyperEVMRateProviderFactory {
    /**
     * @notice A new HyperEVM Rate Provider was created.
     * @param tokenIndex The index of the base asset on the Hyperliquid public API
     * @param pairIndex The index of the pair to fetch the spot price, according to the Hyperliquid public API
     * @param rateProvider The address of the deployed rate provider
     */
    event RateProviderCreated(uint256 indexed tokenIndex, uint256 indexed pairIndex, address indexed rateProvider);

    /// @notice Emitted when the factory is disabled.
    event RateProviderFactoryDisabled();

    /**
     * @notice A rate provider already exists for the given token and pair.
     * @param tokenIndex The index of the base asset on the Hyperliquid public API
     * @param pairIndex The index of the pair to fetch the spot price, according to the Hyperliquid public API
     * @param rateProvider The address of the deployed rate provider
     */
    error RateProviderAlreadyExists(uint32 tokenIndex, uint32 pairIndex, address rateProvider);

    /**
     * @notice The rate provider was not found for the given token and pair.
     * @param tokenIndex The index of the base asset on the Hyperliquid public API
     * @param pairIndex The index of the pair to fetch the spot price, according to the Hyperliquid public API
     */
    error RateProviderNotFound(uint32 tokenIndex, uint32 pairIndex);

    /// @notice The factory is disabled.
    error RateProviderFactoryIsDisabled();

    /**
     * @notice Returns a number representing the rate provider version.
     * @return rateProviderVersion The rate provider version number
     */
    function getRateProviderVersion() external view returns (uint256 rateProviderVersion);

    /**
     * @notice Creates a new HyperEVM Rate Provider for the given token and pair.
     * @param tokenIndex The index of the base asset on the Hyperliquid public API
     * @param pairIndex The index of the pair to fetch the spot price, according to the Hyperliquid public API
     * @return rateProvider The address of the deployed rate provider
     */
    function create(uint32 tokenIndex, uint32 pairIndex) external returns (IHyperEVMRateProvider rateProvider);

    /**
     * @notice Gets the rate provider for the given token and pair.
     * @dev Reverts if the rate provider was not found for the given token and pair.
     * @param tokenIndex The index of the base asset on the Hyperliquid public API
     * @param pairIndex The index of the pair to fetch the spot price, according to the Hyperliquid public API
     * @return rateProvider The address of the rate provider for the given token and pair
     */
    function getRateProvider(
        uint32 tokenIndex,
        uint32 pairIndex
    ) external view returns (IHyperEVMRateProvider rateProvider);

    /**
     * @notice Checks whether the given rate provider was created by this factory.
     * @param rateProvider The rate provider to check
     * @return success True if the rate provider was created by this factory; false otherwise
     */
    function isRateProviderFromFactory(IHyperEVMRateProvider rateProvider) external view returns (bool success);

    /**
     * @notice Disables the rate provider factory.
     * @dev A disabled rate provider factory cannot create new rate providers and cannot be re-enabled. However,
     * already created rate providers are still usable. This is a permissioned function.
     */
    function disable() external;
}
