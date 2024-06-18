// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "../solidity-utils/helpers/IAuthentication.sol";

interface IBasePoolFactory is IAuthentication {
    /**
     * @notice A pool was deployed.
     * @param pool The address of the new pool
     */
    event PoolCreated(address indexed pool);

    /// @notice The factory was disabled by governance.
    event FactoryDisabled();

    /// @notice Cannot create a pool after the factory was disabled.
    error Disabled();

    /**
     * @notice Check whether a pool was deployed by this factory.
     * @param pool The pool to check
     * @return  True if `pool` was created by this factory
     */
    function isPoolFromFactory(address pool) external view returns (bool);

    /**
     * @notice Return the address where a new pool will be deployed, based on the factory address and salt.
     * @param salt The salt used to deploy the pool
     */
    function getDeploymentAddress(bytes32 salt) external view returns (address);

    /**
     * @notice Check whether this factory has been disabled by governance.
     * @return  True if this factory was disabled
     */
    function isDisabled() external view returns (bool);

    /**
     * @notice Disable the factory, preventing the creation of more pools.
     * @dev Existing pools are unaffected. Once a factory is disabled, it cannot be re-enabled.
     */
    function disable() external;
}
