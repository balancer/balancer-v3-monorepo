// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IBasePoolFactory } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePoolFactory.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import {
    SingletonAuthentication
} from "@balancer-labs/v3-solidity-utils/contracts/helpers/SingletonAuthentication.sol";
import { CREATE3 } from "@balancer-labs/v3-solidity-utils/contracts/solmate/CREATE3.sol";

import { FactoryWidePauseWindow } from "./FactoryWidePauseWindow.sol";

/**
 * @notice Base contract for Pool factories.
 *
 * Pools are deployed from factories to allow third parties to reason about them. Unknown Pools may have arbitrary
 * logic: being able to assert that a Pool's behavior follows certain rules (those imposed by the contracts created by
 * the factory) is very powerful.
 *
 * Since we expect to release new versions of pool types regularly - and the blockchain is forever - versioning will
 * become increasingly important. Governance can deprecate a factory by calling `disable`, which will permanently
 * prevent the creation of any future pools from the factory.
 */
abstract contract BasePoolFactory is IBasePoolFactory, SingletonAuthentication, FactoryWidePauseWindow {
    mapping(address => bool) private _isPoolFromFactory;
    bool private _disabled;

    // Store the creationCode of the contract to be deployed by create3.
    bytes private _creationCode;

    constructor(
        IVault vault,
        uint256 pauseWindowDuration,
        bytes memory creationCode
    ) SingletonAuthentication(vault) FactoryWidePauseWindow(pauseWindowDuration) {
        _creationCode = creationCode;
    }

    /// @inheritdoc IBasePoolFactory
    function isPoolFromFactory(address pool) external view returns (bool) {
        return _isPoolFromFactory[pool];
    }

    /// @inheritdoc IBasePoolFactory
    function isDisabled() public view returns (bool) {
        return _disabled;
    }

    /// @inheritdoc IBasePoolFactory
    function getDeploymentAddress(bytes32 salt) external view returns (address) {
        return CREATE3.getDeployed(_computeFinalSalt(salt));
    }

    /// @inheritdoc IBasePoolFactory
    function disable() external authenticate {
        _ensureEnabled();

        _disabled = true;

        emit FactoryDisabled();
    }

    function _ensureEnabled() internal view {
        if (isDisabled()) {
            revert Disabled();
        }
    }

    function _registerPoolWithFactory(address pool) internal virtual {
        _ensureEnabled();

        _isPoolFromFactory[pool] = true;

        emit PoolCreated(pool);
    }

    function _computeFinalSalt(bytes32 salt) internal view returns (bytes32) {
        return keccak256(abi.encode(msg.sender, block.chainid, salt));
    }

    function _create(bytes memory constructorArgs, bytes32 salt) internal returns (address) {
        return CREATE3.deploy(_computeFinalSalt(salt), abi.encodePacked(_creationCode, constructorArgs), 0);
    }
}
