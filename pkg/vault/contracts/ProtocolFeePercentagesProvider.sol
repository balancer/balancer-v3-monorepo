// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {
    IProtocolFeePercentagesProvider
} from "@balancer-labs/v3-interfaces/contracts/vault/IProtocolFeePercentagesProvider.sol";
import { IProtocolFeeController } from "@balancer-labs/v3-interfaces/contracts/vault/IProtocolFeeController.sol";
import { IBasePoolFactory } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePoolFactory.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { SingletonAuthentication } from "./SingletonAuthentication.sol";

contract ProtocolFeePercentagesProvider is IProtocolFeePercentagesProvider, SingletonAuthentication {
    using SafeCast for uint256;

    /// @notice The protocol fee controller was configured with an incorrect Vault address.
    error WrongProtocolFeeControllerDeployment();

    /**
     * @dev Data structure to store default protocol fees by factory. Fee percentages are 18-decimal floating point
     * numbers, so we know they fit in 64 bits, allowing the fees to be stored in a single slot.
     *
     * @param protocolSwapFee The protocol swap fee
     * @param protocolYieldFee The protocol yield fee
     * @param isFactoryRegistered Flag indicating fees have been set (allows zero values)
     */
    struct FactoryProtocolFees {
        uint64 protocolSwapFeePercentage;
        uint64 protocolYieldFeePercentage;
        bool isFactoryRegistered;
    }

    IProtocolFeeController private immutable _protocolFeeController;

    uint256 private immutable _maxProtocolSwapFeePercentage;
    uint256 private immutable _maxProtocolYieldFeePercentage;

    // Factory address => FactoryProtocolFees
    mapping(IBasePoolFactory => FactoryProtocolFees) private _factoryDefaultFeePercentages;

    constructor(IVault vault, IProtocolFeeController protocolFeeController) SingletonAuthentication(vault) {
        _protocolFeeController = protocolFeeController;

        if (protocolFeeController.vault() != vault) {
            revert WrongProtocolFeeControllerDeployment();
        }

        // These values are constant in the `ProtocolFeeController`.
        (_maxProtocolSwapFeePercentage, _maxProtocolYieldFeePercentage) = protocolFeeController
            .getMaximumProtocolFeePercentages();
    }

    /// @inheritdoc IProtocolFeePercentagesProvider
    function getProtocolFeeController() external view returns (IProtocolFeeController) {
        return _protocolFeeController;
    }

    /// @inheritdoc IProtocolFeePercentagesProvider
    function getFactorySpecificProtocolFeePercentages(
        address factory
    ) external view returns (uint256 protocolSwapFeePercentage, uint256 protocolYieldFeePercentage) {
        FactoryProtocolFees memory factoryFees = _getValidatedProtocolFees(factory);

        protocolSwapFeePercentage = factoryFees.protocolSwapFeePercentage;
        protocolYieldFeePercentage = factoryFees.protocolYieldFeePercentage;
    }

    /// @inheritdoc IProtocolFeePercentagesProvider
    function setFactorySpecificProtocolFeePercentages(
        address factory,
        uint256 protocolSwapFeePercentage,
        uint256 protocolYieldFeePercentage
    ) external authenticate {
        // Validate the fee percentages; don't store values that the `ProtocolFeeCollector` will reject.
        if (protocolSwapFeePercentage > _maxProtocolSwapFeePercentage) {
            revert IProtocolFeeController.ProtocolSwapFeePercentageTooHigh();
        }

        if (protocolYieldFeePercentage > _maxProtocolYieldFeePercentage) {
            revert IProtocolFeeController.ProtocolYieldFeePercentageTooHigh();
        }

        // Ensure precision checks will pass.
        _protocolFeeController.ensureValidPrecision(protocolSwapFeePercentage);
        _protocolFeeController.ensureValidPrecision(protocolYieldFeePercentage);

        // Best effort check that `factory` is the address of an IBasePoolFactory.
        bool poolFromFactory = IBasePoolFactory(factory).isPoolFromFactory(address(0));
        if (poolFromFactory) {
            revert InvalidFactory(factory);
        }

        // Store the default fee percentages, and mark the factory as registered.
        _factoryDefaultFeePercentages[IBasePoolFactory(factory)] = FactoryProtocolFees({
            protocolSwapFeePercentage: protocolSwapFeePercentage.toUint64(),
            protocolYieldFeePercentage: protocolYieldFeePercentage.toUint64(),
            isFactoryRegistered: true
        });

        emit FactorySpecificProtocolFeePercentagesSet(factory, protocolSwapFeePercentage, protocolYieldFeePercentage);
    }

    /// @inheritdoc IProtocolFeePercentagesProvider
    function setProtocolFeePercentagesForPools(address factory, address[] memory pools) external {
        FactoryProtocolFees memory factoryFees = _getValidatedProtocolFees(factory);

        for (uint256 i = 0; i < pools.length; ++i) {
            address currentPool = pools[i];

            if (IBasePoolFactory(factory).isPoolFromFactory(currentPool) == false) {
                revert PoolNotFromFactory(currentPool, factory);
            }

            _setPoolProtocolFees(
                currentPool,
                factoryFees.protocolSwapFeePercentage,
                factoryFees.protocolYieldFeePercentage
            );
        }
    }

    function _getValidatedProtocolFees(address factory) private view returns (FactoryProtocolFees memory factoryFees) {
        factoryFees = _factoryDefaultFeePercentages[IBasePoolFactory(factory)];

        if (factoryFees.isFactoryRegistered == false) {
            revert FactoryNotRegistered(factory);
        }
    }

    // These are permissioned functions on `ProtocolFeeController`, so governance will need to allow this contract
    // to call `setProtocolSwapFeePercentage` and `setProtocolYieldFeePercentage`.
    function _setPoolProtocolFees(
        address pool,
        uint256 protocolSwapFeePercentage,
        uint256 protocolYieldFeePercentage
    ) private {
        _protocolFeeController.setProtocolSwapFeePercentage(pool, protocolSwapFeePercentage);
        _protocolFeeController.setProtocolYieldFeePercentage(pool, protocolYieldFeePercentage);
    }
}
