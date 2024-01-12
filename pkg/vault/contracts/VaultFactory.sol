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
    error VaultFactoryIsDisabled();

    error VaultAddressMismatch();

    bool public isDisabled;

    IAuthorizer private immutable _authorizer;
    uint256 private immutable _pauseWindowDuration;
    uint256 private immutable _bufferPeriodDuration;
    bytes32 private immutable _finalSalt;
    address private immutable _vaultAddress;

    bytes private _creationCode;

    // solhint-disable not-rely-on-time

    constructor(
        bytes32 salt,
        address targetAddress,
        IAuthorizer authorizer,
        uint256 pauseWindowDuration,
        uint256 bufferPeriodDuration
    ) {
        _finalSalt = keccak256(abi.encode(msg.sender, salt));
        address vaultAddress = CREATE3.getDeployed(_finalSalt);
        if (targetAddress != vaultAddress) {
            revert VaultAddressMismatch();
        }

        _vaultAddress = vaultAddress;
        _creationCode = type(Vault).creationCode;
        _authorizer = authorizer;
        _pauseWindowDuration = pauseWindowDuration;
        _bufferPeriodDuration = bufferPeriodDuration;
    }

    /**
     * @notice Deploys the Vault.
     */
    function create() external {
        if (isDisabled) {
            revert VaultFactoryIsDisabled();
        }
        isDisabled = true;

        VaultExtension vaultExtension = new VaultExtension(_vaultAddress);
        _create(abi.encode(vaultExtension, _authorizer, _pauseWindowDuration, _bufferPeriodDuration));
    }

    function getDeploymentAddress() external view returns (address) {
        return _vaultAddress;
    }

    function _create(bytes memory constructorArgs) internal returns (address) {
        return CREATE3.deploy(_finalSalt, abi.encodePacked(_creationCode, constructorArgs), 0);
    }
}
