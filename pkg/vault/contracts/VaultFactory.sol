// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IAuthorizer } from "@balancer-labs/v3-interfaces/contracts/vault/IAuthorizer.sol";
import { Authentication } from "@balancer-labs/v3-solidity-utils/contracts/helpers/Authentication.sol";
import { CREATE3 } from "@balancer-labs/v3-solidity-utils/contracts/solmate/CREATE3.sol";

import { Vault } from "./Vault.sol";
import { VaultExtension } from "./VaultExtension.sol";

/**
 * @dev One-off factory to deploy the Vault at a specific address.
 */
contract VaultFactory is Authentication {
    event VaultCreated(address);

    error VaultFactoryIsDisabled();

    error VaultAddressMismatch();

    bool public isDisabled;

    IAuthorizer private immutable _authorizer;
    uint256 private immutable _pauseWindowDuration;
    uint256 private immutable _bufferPeriodDuration;
    address private immutable _deployer;

    bytes private _creationCode;

    // solhint-disable not-rely-on-time

    constructor(
        IAuthorizer authorizer,
        uint256 pauseWindowDuration,
        uint256 bufferPeriodDuration
    ) Authentication(bytes32(uint256(uint160(address(this))))) {
        _deployer = msg.sender;
        _creationCode = type(Vault).creationCode;
        _authorizer = authorizer;
        _pauseWindowDuration = pauseWindowDuration;
        _bufferPeriodDuration = bufferPeriodDuration;
    }

    /**
     * @notice Deploys the Vault.
     */
    function create(bytes32 salt, address targetAddress) external authenticate {
        if (isDisabled) {
            revert VaultFactoryIsDisabled();
        }
        isDisabled = true;

        address vaultAddress = getDeploymentAddress(salt);
        if (targetAddress != vaultAddress) {
            revert VaultAddressMismatch();
        }

        VaultExtension vaultExtension = new VaultExtension(vaultAddress);
        _create(abi.encode(vaultExtension, _authorizer, _pauseWindowDuration, _bufferPeriodDuration), salt);

        emit VaultCreated(vaultAddress);
    }

    function getDeploymentAddress(bytes32 salt) public view returns (address) {
        return CREATE3.getDeployed(salt);
    }

    function _create(bytes memory constructorArgs, bytes32 finalSalt) internal returns (address) {
        return CREATE3.deploy(finalSalt, abi.encodePacked(_creationCode, constructorArgs), 0);
    }

    function _canPerform(bytes32 actionId, address user) internal view virtual override returns (bool) {
        return _authorizer.canPerform(actionId, user, address(this));
    }
}
