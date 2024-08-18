// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IProtocolFeeController } from "./IProtocolFeeController.sol";

interface IProtocolFeePercentagesProvider {
    /**
     * @notice `setFactorySpecificProtocolFeePercentages` has not been called for this factory address.
     * @dev This error can by thrown by `getFactorySpecificProtocolFeePercentages` or
     * `setProtocolFeePercentagesForPools`, as both require that valid fee percentages have been set.
     *
     * @param factory The unregistered factory address
     */
    error FactoryNotRegistered(address factory);

    /**
     * @notice The factory address provided is not a valid `IBasePoolFactory`.
     * @dev This means it responds incorrectly to `isPoolFromFactory` (e.g., always responds true). If it doesn't
     * implement `isPoolFromFactory` or isn't a contract at all, calls on `setFactorySpecificProtocolFeePercentages`
     * will revert with no data.
     *
     * @param factory The address of the invalid factory
     */
    error InvalidFactory(address factory);

    /**
     * @notice The given pool is not from the expected factory.
     * @dev Occurs when one of the pools supplied to `setProtocolFeePercentagesForPools` is not from the given factory.
     * @param pool The address of the unrecognized pool
     * @param factory The address of the factory
     */
    error PoolNotFromFactory(address pool, address factory);

    /**
     * @notice Get the address of the `ProtocolFeeController` used to set fees.
     * @return protocolFeeController The address of the fee controller
     */
    function getProtocolFeeController() external view returns (IProtocolFeeController);

    /**
     * @notice Query the protocol fee percentages for a given factory.
     * @param factory The address of the factory
     * @return protocolSwapFeePercentage The protocol swap fee percentage set for that factory
     * @return protocolYieldFeePercentage The protocol yield fee percentage set for that factory
     */
    function getFactorySpecificProtocolFeePercentages(
        address factory
    ) external view returns (uint256 protocolSwapFeePercentage, uint256 protocolYieldFeePercentage);

    /**
     * @notice Assign intended protocol fee percentages for a given factory.
     * @dev This is a permissioned call. After the fee percentages have been set, and governance has granted
     * this contract permission to set fee percentages on pools, anyone can call `setProtocolFeePercentagesForPools`
     * to update the fee percentages on a set of pools from that factory.
     *
     * @param factory The address of the factory
     * @param protocolSwapFeePercentage The new protocol swap fee percentage
     * @param protocolYieldFeePercentage The new protocol yield fee percentage
     */
    function setFactorySpecificProtocolFeePercentages(
        address factory,
        uint256 protocolSwapFeePercentage,
        uint256 protocolYieldFeePercentage
    ) external;

    /**
     * @notice Update the protocol fees for a set of pools from a given factory.
     * @dev This call is permissionless. Anyone can update the fee percentages, once they're set by governance.
     * Note that goverance must also grant this contract permmission to set protocol fee percentages on pools.
     *
     * @param factory The address of the factory
     * @param pools The pools whose fees will be set according to `setFactorySpecificProtocolFeePercentages`
     */
    function setProtocolFeePercentagesForPools(address factory, address[] memory pools) external;
}
