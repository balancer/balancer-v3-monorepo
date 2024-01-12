// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IAuthorizer } from "@balancer-labs/v3-interfaces/contracts/vault/IAuthorizer.sol";
import { CREATE3 } from "@balancer-labs/v3-solidity-utils/contracts/solmate/CREATE3.sol";

import { Vault } from "./Vault.sol";
import { VaultExtension } from "./VaultExtension.sol";

/**
 * @dev One-off factory to deploy the Vault at a specific address.
 */
contract VaultFactory {
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
    ) {
        _deployer = msg.sender;
        _creationCode = type(Vault).creationCode;
        _authorizer = authorizer;
        _pauseWindowDuration = pauseWindowDuration;
        _bufferPeriodDuration = bufferPeriodDuration;
    }

    /**
     * @notice Deploys the Vault.
     */
    function create(
        bytes32 salt,
        address targetAddress
    ) external {
        if (isDisabled) {
            revert VaultFactoryIsDisabled();
        }
        isDisabled = true;

        bytes32 finalSalt = _computeFinalSalt(salt);
        address vaultAddress = _getDeploymentAddress(finalSalt);
        if (targetAddress != vaultAddress) {
            revert VaultAddressMismatch();
        }

        VaultExtension vaultExtension = new VaultExtension(vaultAddress);
        _create(abi.encode(vaultExtension, _authorizer, _pauseWindowDuration, _bufferPeriodDuration), finalSalt);

        emit VaultCreated(vaultAddress);
    }

    function getDeploymentAddress(bytes32 salt) external view returns (address) {
        return _getDeploymentAddress(_computeFinalSalt(salt));
     }

    function _getDeploymentAddress(bytes32 finalSalt) internal view returns (address) {
        return CREATE3.getDeployed(finalSalt);
     }

    function _computeFinalSalt(bytes32 salt) internal view returns (bytes32) {
        return keccak256(abi.encode(msg.sender, salt));
    }
    function _create(bytes memory constructorArgs, bytes32 finalSalt) internal returns (address) {
        return CREATE3.deploy(finalSalt, abi.encodePacked(_creationCode, constructorArgs), 0);
    }
}
