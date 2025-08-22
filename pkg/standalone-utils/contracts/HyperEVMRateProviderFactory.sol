// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import {
    IHyperEVMRateProviderFactory
} from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IHyperEVMRateProviderFactory.sol";
import {
    IHyperEVMRateProvider
} from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IHyperEVMRateProvider.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { SingletonAuthentication } from "@balancer-labs/v3-vault/contracts/SingletonAuthentication.sol";
import { Version } from "@balancer-labs/v3-solidity-utils/contracts/helpers/Version.sol";

import { HyperEVMRateProvider } from "./HyperEVMRateProvider.sol";

/// @notice Factory for deploying and managing HyperEVM rate providers.
contract HyperEVMRateProviderFactory is IHyperEVMRateProviderFactory, SingletonAuthentication, Version {
    uint256 internal immutable _rateProviderVersion;
    bool internal _isDisabled;

    mapping(bytes32 rateProviderId => IHyperEVMRateProvider rateProvider) internal _rateProviders;
    mapping(IHyperEVMRateProvider rateProvider => bool creationFlag) internal _isRateProviderFromFactory;

    constructor(
        IVault vault,
        string memory factoryVersion,
        uint256 rateProviderVersion
    ) SingletonAuthentication(vault) Version(factoryVersion) {
        _rateProviderVersion = rateProviderVersion;
    }

    /// @inheritdoc IHyperEVMRateProviderFactory
    function getRateProviderVersion() external view returns (uint256) {
        return _rateProviderVersion;
    }

    /// @inheritdoc IHyperEVMRateProviderFactory
    function create(uint32 tokenIndex, uint32 pairIndex) external returns (IHyperEVMRateProvider rateProvider) {
        _ensureEnabled();

        bytes32 rateProviderId = _computeRateProviderId(tokenIndex, pairIndex);

        address existingRateProvider = address(_rateProviders[rateProviderId]);

        if (existingRateProvider != address(0)) {
            revert RateProviderAlreadyExists(tokenIndex, pairIndex, existingRateProvider);
        }

        rateProvider = IHyperEVMRateProvider(address(new HyperEVMRateProvider(tokenIndex, pairIndex)));
        _rateProviders[rateProviderId] = rateProvider;
        _isRateProviderFromFactory[rateProvider] = true;

        emit RateProviderCreated(tokenIndex, pairIndex, address(rateProvider));
    }

    /// @inheritdoc IHyperEVMRateProviderFactory
    function getRateProvider(
        uint32 tokenIndex,
        uint32 pairIndex
    ) external view returns (IHyperEVMRateProvider rateProvider) {
        bytes32 rateProviderId = _computeRateProviderId(tokenIndex, pairIndex);
        rateProvider = _rateProviders[rateProviderId];
        if (address(rateProvider) == address(0)) {
            revert RateProviderNotFound(tokenIndex, pairIndex);
        }
        return rateProvider;
    }

    /// @inheritdoc IHyperEVMRateProviderFactory
    function isRateProviderFromFactory(IHyperEVMRateProvider rateProvider) external view returns (bool) {
        return _isRateProviderFromFactory[rateProvider];
    }

    /// @inheritdoc IHyperEVMRateProviderFactory
    function disable() external authenticate {
        _ensureEnabled();

        _isDisabled = true;
        emit RateProviderFactoryDisabled();
    }

    function _computeRateProviderId(uint32 tokenIndex, uint32 pairIndex) internal pure returns (bytes32) {
        return keccak256(abi.encode(tokenIndex, pairIndex));
    }

    function _ensureEnabled() internal view {
        if (_isDisabled) {
            revert RateProviderFactoryIsDisabled();
        }
    }
}
