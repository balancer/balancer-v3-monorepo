// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { IProtocolFeeController } from "@balancer-labs/v3-interfaces/contracts/vault/IProtocolFeeController.sol";
import { IBasePoolFactory } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePoolFactory.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import {
    SingletonAuthentication
} from "@balancer-labs/v3-solidity-utils/contracts/helpers/SingletonAuthentication.sol";
import { EnumerableSet } from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/EnumerableSet.sol";

contract ProtocolFeePercentagesProvider is SingletonAuthentication {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeCast for uint256;

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

    // Iterable list of the factories with default fees set.
    EnumerableSet.AddressSet private _factories;

    /// @notice The protocol fee controller was configured with an incorrect Vault address.
    error WrongProtocolFeeControllerDeployment();

    /**
     * @notice `setDefaultProtocolFees` has not been called for this factory address.
     * @param factory The unregistered factory address
     */
    error FactoryNotRegistered(address factory);

    /**
     * @notice The factory address provided is not a valid IBasePoolFactory.
     * @dev This means it does not implement or responds incorrectly to `isPoolFromFactory`.
     * @param factory The address of the invalid factory
     */
    error InvalidFactory(address factory);

    /**
     * @notice The given pool is not from any of the registered factories.
     * @param pool The address of the pool
     */
    error PoolNotFromRegisteredFactory(address pool);

    constructor(IVault vault, IProtocolFeeController protocolFeeController) SingletonAuthentication(vault) {
        _protocolFeeController = protocolFeeController;

        if (protocolFeeController.vault() != vault) {
            revert WrongProtocolFeeControllerDeployment();
        }

        // These values are constant in the `ProtocolFeeController`.
        (_maxProtocolSwapFeePercentage, _maxProtocolYieldFeePercentage) = protocolFeeController
            .getMaximumProtocolFeePercentages();
    }

    function getProtocolFeeController() external view returns (IProtocolFeeController) {
        return _protocolFeeController;
    }

    function getFactorySpecificProtocolFees(
        address factory
    ) external view returns (uint256 protocolSwapFeePercentage, uint256 protocolYieldFeePercentage) {
        FactoryProtocolFees memory factoryFees = _getValidatedProtocolFees(factory);

        protocolSwapFeePercentage = factoryFees.protocolSwapFeePercentage;
        protocolYieldFeePercentage = factoryFees.protocolYieldFeePercentage;
    }

    function setProtocolFeesForPools(address factory, address[] memory pools) external {
        FactoryProtocolFees memory factoryFees = _getValidatedProtocolFees(factory);

        for (uint256 i = 0; i < pools.length; ++i) {
            address currentPool = pools[i];

            if (IBasePoolFactory(factory).isPoolFromFactory(currentPool) == false) {
                revert PoolNotFromRegisteredFactory(currentPool);
            }

            _setPoolProtocolFees(
                currentPool,
                factoryFees.protocolSwapFeePercentage,
                factoryFees.protocolYieldFeePercentage
            );
        }
    }

    function setProtocolFeesForPools(address[] memory pools) external {
        uint256 numPools = pools.length;

        if (numPools > 0) {
            address currentPool = pools[0];

            (
                IBasePoolFactory currentFactory,
                uint256 protocolSwapFeePercentage,
                uint256 protocolYieldFeePercentage
            ) = _findFactoryForPool(currentPool);

            _setPoolProtocolFees(currentPool, protocolSwapFeePercentage, protocolYieldFeePercentage);

            // Common usage will be to call this for pools from the same factory. Or at a minimum, the pools will be
            // grouped by factory. Check to see whether subsequent pools are from the `currentFactory`, to make as few
            // expensive calls to `_findFactoryForPool` as possible. You can call this with an unordered set of pools,
            // but it will be more expensive.
            for (uint256 i = 1; i < numPools; ++i) {
                currentPool = pools[i];

                if (currentFactory.isPoolFromFactory(currentPool) == false) {
                    (currentFactory, protocolSwapFeePercentage, protocolYieldFeePercentage) = _findFactoryForPool(
                        currentPool
                    );
                }

                _setPoolProtocolFees(currentPool, protocolSwapFeePercentage, protocolYieldFeePercentage);
            }
        }
    }

    function setFactorySpecificProtocolFees(
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

        // Best effort check that the factory is an IBasePoolFactory.
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

        // Add to iterable set. Ignore return value; it's possible to call this multiple times on a factory to update
        // the fee percentages.
        _factories.add(factory);
    }

    function _findFactoryForPool(address pool) private view returns (IBasePoolFactory, uint256, uint256) {
        uint256 numFactories = _factories.length();
        IBasePoolFactory basePoolFactory;

        for (uint256 i = 0; i < numFactories; ++i) {
            basePoolFactory = IBasePoolFactory(_factories.unchecked_at(i));

            if (basePoolFactory.isPoolFromFactory(pool)) {
                FactoryProtocolFees memory fees = _factoryDefaultFeePercentages[basePoolFactory];

                return (basePoolFactory, fees.protocolSwapFeePercentage, fees.protocolYieldFeePercentage);
            }
        }

        revert PoolNotFromRegisteredFactory(pool);
    }

    function _getValidatedProtocolFees(address factory) private view returns (FactoryProtocolFees memory factoryFees) {
        factoryFees = _factoryDefaultFeePercentages[IBasePoolFactory(factory)];

        if (factoryFees.isFactoryRegistered == false) {
            revert FactoryNotRegistered(factory);
        }
    }

    // These are permissioned functions on `ProtocolFeeController`, so governance will need to allow this contract
    // to call `setProtocolSwapFeePercentage` and `setProtocolYieldFeePercentage`.
    function _setPoolProtocolFees(address pool, uint256 protocolSwapFee, uint256 protocolYieldFee) private {
        _protocolFeeController.setProtocolSwapFeePercentage(pool, protocolSwapFee);
        _protocolFeeController.setProtocolYieldFeePercentage(pool, protocolYieldFee);
    }
}
