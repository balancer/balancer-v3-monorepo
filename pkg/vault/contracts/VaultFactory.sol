// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IAuthorizer } from "@balancer-labs/v3-interfaces/contracts/vault/IAuthorizer.sol";
import { CREATE3 } from "@balancer-labs/v3-solidity-utils/contracts/solmate/CREATE3.sol";

import { Vault } from "./Vault.sol";
import { VaultExtension } from "./VaultExtension.sol";

/**
 * @dev One-off factory to deploy the Vault at a specific address.
 */
contract VaultFactory is Ownable {
    bool public isDisabled;

    IAuthorizer private immutable _authorizer;
    uint256 private immutable _pauseWindowDuration;
    uint256 private immutable _bufferPeriodDuration;

    bytes private _creationCode;

    // solhint-disable not-rely-on-time

    constructor(
        IAuthorizer authorizer,
        uint256 pauseWindowDuration,
        uint256 bufferPeriodDuration
    ) Ownable(msg.sender) {
        _creationCode = type(Vault).creationCode;
        _authorizer = authorizer;
        _pauseWindowDuration = pauseWindowDuration;
        _bufferPeriodDuration = bufferPeriodDuration;
    }

    /**
     * @notice Deploys the Vault.
     * @param salt The salt value that will be passed to create3 deployment
     */
    function create(
        bytes32 salt
    ) external returns (address vaultAddress) {
        vaultAddress = getDeploymentAddress(salt);
        VaultExtension vaultExtension = new VaultExtension(vaultAddress);
        return _create(abi.encode(vaultExtension, _authorizer, _pauseWindowDuration, _bufferPeriodDuration), salt);
    }

    function getDeploymentAddress(bytes32 salt) public view returns (address) {
        return CREATE3.getDeployed(salt);
    }

    function _create(bytes memory constructorArgs, bytes32 salt) internal returns (address) {
        return CREATE3.deploy(salt, abi.encodePacked(_creationCode, constructorArgs), 0);
    }
}
