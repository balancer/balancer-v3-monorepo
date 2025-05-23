// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { IProtocolFeeController } from "@balancer-labs/v3-interfaces/contracts/vault/IProtocolFeeController.sol";
import { IBasePoolFactory } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePoolFactory.sol";
import { FEE_SCALING_FACTOR } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import {
    IProtocolFeePercentagesProvider
} from "@balancer-labs/v3-interfaces/contracts/vault/IProtocolFeePercentagesProvider.sol";
import {
    IBalancerContractRegistry,
    ContractType
} from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IBalancerContractRegistry.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { SingletonAuthentication } from "@balancer-labs/v3-vault/contracts/SingletonAuthentication.sol";
import { ProtocolFeeController } from "@balancer-labs/v3-vault/contracts/ProtocolFeeController.sol";

contract ProtocolFeePercentagesProvider is IProtocolFeePercentagesProvider, SingletonAuthentication {
    using SafeCast for uint256;

    /**
     * @dev Data structure to store default protocol fees by factory. Fee percentages are 18-decimal floating point
     * numbers, so we know they fit in 64 bits, allowing the fees to be stored in a single slot.
     *
     * @param protocolSwapFee The protocol swap fee
     * @param protocolYieldFee The protocol yield fee
     * @param areFactoryFeesSet Flag indicating fees have been set (allows zero values)
     */
    struct FactoryProtocolFees {
        uint64 protocolSwapFeePercentage;
        uint64 protocolYieldFeePercentage;
        bool areFactoryFeesSet;
    }

    IBalancerContractRegistry private immutable _trustedContractRegistry;
    IProtocolFeeController private immutable _protocolFeeController;

    uint256 private immutable _maxProtocolSwapFeePercentage;
    uint256 private immutable _maxProtocolYieldFeePercentage;

    // Factory address => FactoryProtocolFees
    mapping(IBasePoolFactory => FactoryProtocolFees) private _factoryDefaultFeePercentages;

    constructor(IVault vault, IBalancerContractRegistry trustedContractRegistry) SingletonAuthentication(vault) {
        IProtocolFeeController protocolFeeController = vault.getProtocolFeeController();

        _protocolFeeController = protocolFeeController;
        _trustedContractRegistry = trustedContractRegistry;

        // Read the maximum percentages from the `protocolFeeController`.
        _maxProtocolSwapFeePercentage = ProtocolFeeController(address(protocolFeeController))
            .MAX_PROTOCOL_SWAP_FEE_PERCENTAGE();
        _maxProtocolYieldFeePercentage = ProtocolFeeController(address(protocolFeeController))
            .MAX_PROTOCOL_YIELD_FEE_PERCENTAGE();
    }

    /// @inheritdoc IProtocolFeePercentagesProvider
    function getProtocolFeeController() external view returns (IProtocolFeeController) {
        return _protocolFeeController;
    }

    /// @inheritdoc IProtocolFeePercentagesProvider
    function getBalancerContractRegistry() external view returns (IBalancerContractRegistry) {
        return _trustedContractRegistry;
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

        // Ensure the factory is valid.
        if (_trustedContractRegistry.isActiveBalancerContract(ContractType.POOL_FACTORY, factory) == false) {
            revert UnknownFactory(factory);
        }

        // Ensure precision checks will pass.
        _ensureValidPrecision(protocolSwapFeePercentage);
        _ensureValidPrecision(protocolYieldFeePercentage);

        // Store the default fee percentages, and mark the factory as registered.
        _factoryDefaultFeePercentages[IBasePoolFactory(factory)] = FactoryProtocolFees({
            protocolSwapFeePercentage: protocolSwapFeePercentage.toUint64(),
            protocolYieldFeePercentage: protocolYieldFeePercentage.toUint64(),
            areFactoryFeesSet: true
        });

        emit FactorySpecificProtocolFeePercentagesSet(factory, protocolSwapFeePercentage, protocolYieldFeePercentage);
    }

    /// @inheritdoc IProtocolFeePercentagesProvider
    function setProtocolFeePercentagesForPools(address factory, address[] memory pools) external {
        // Note that unless the factory fees were previously set in `setFactorySpecificProtocolFeePercentages` above,
        // this getter will revert. The fee setter function validates the factory with the `BalancerContractRegistry`,
        // so we know it is a valid Balancer pool factory.
        FactoryProtocolFees memory factoryFees = _getValidatedProtocolFees(factory);

        for (uint256 i = 0; i < pools.length; ++i) {
            address currentPool = pools[i];

            // We know from the logic above that the factory is valid. Now also check that the given pool actually
            // comes from that factory.
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

        if (factoryFees.areFactoryFeesSet == false) {
            revert FactoryFeesNotSet(factory);
        }
    }

    /**
     * @dev These are permissioned functions on `ProtocolFeeController`, so governance will need to allow this contract
     * to call `setProtocolSwapFeePercentage` and `setProtocolYieldFeePercentage`.
     */
    function _setPoolProtocolFees(
        address pool,
        uint256 protocolSwapFeePercentage,
        uint256 protocolYieldFeePercentage
    ) private {
        _protocolFeeController.setProtocolSwapFeePercentage(pool, protocolSwapFeePercentage);
        _protocolFeeController.setProtocolYieldFeePercentage(pool, protocolYieldFeePercentage);
    }

    /**
     * @dev This is a duplicate of the corresponding function in `ProtocolFeeController`, as it isn't exposed in the
     * deployed version of the contract.
     */
    function _ensureValidPrecision(uint256 feePercentage) private pure {
        // Primary fee percentages are 18-decimal values, stored here in 64 bits, and calculated with full 256-bit
        // precision. However, the resulting aggregate fees are stored in the Vault with 24-bit precision, which
        // corresponds to 0.00001% resolution (i.e., a fee can be 1%, 1.00001%, 1.00002%, but not 1.000005%).
        // Ensure there will be no precision loss in the Vault - which would lead to a discrepancy between the
        // aggregate fee calculated here and that stored in the Vault.
        if ((feePercentage / FEE_SCALING_FACTOR) * FEE_SCALING_FACTOR != feePercentage) {
            revert IVaultErrors.FeePrecisionTooHigh();
        }
    }
}
