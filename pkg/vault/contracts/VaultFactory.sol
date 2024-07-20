// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { Iv2Vault } from "@balancer-labs/v3-interfaces/contracts/vault/Iv2Vault.sol";
import { Authentication } from "@balancer-labs/v3-solidity-utils/contracts/helpers/Authentication.sol";
import { CREATE3 } from "@balancer-labs/v3-solidity-utils/contracts/solmate/CREATE3.sol";

import { Vault } from "./Vault.sol";
import { VaultAdmin } from "./VaultAdmin.sol";
import { VaultExtension } from "./VaultExtension.sol";
import { ProtocolFeeController } from "./ProtocolFeeController.sol";

/**
 * @dev One-off factory to deploy the Vault at a specific address.
 */
contract VaultFactory is Authentication {
    /// @dev Emitted when the Vault is deployed.
    event VaultCreated(address);

    /// @dev Vault has already been deployed, so this factory is disabled.
    error VaultAlreadyCreated();

    /// @dev The given salt does not match the generated address when attempting to create the Vault.
    error VaultAddressMismatch();

    bool public isDisabled;

    Iv2Vault private immutable _v2Vault;
    uint32 private immutable _pauseWindowDuration;
    uint32 private immutable _bufferPeriodDuration;
    address private immutable _deployer;

    bytes private _creationCode;

    // solhint-disable not-rely-on-time

    constructor(
        Iv2Vault v2Vault,
        uint32 pauseWindowDuration,
        uint32 bufferPeriodDuration
    ) Authentication(bytes32(uint256(uint160(address(this))))) {
        _deployer = msg.sender;
        _creationCode = type(Vault).creationCode;
        _v2Vault = v2Vault;
        _pauseWindowDuration = pauseWindowDuration;
        _bufferPeriodDuration = bufferPeriodDuration;
    }

    /**
     * @notice Deploys the Vault.
     * @dev The Vault can only be deployed once. Therefore, this function is permissioned to ensure that it is
     * deployed to the right address.
     * @param salt Salt used to create the vault. See `getDeploymentAddress`.
     * @param targetAddress Expected Vault address. The function will revert if the given salt does not deploy the
     * Vault to the target address.
     */
    function create(bytes32 salt, address targetAddress) external authenticate {
        if (isDisabled) {
            revert VaultAlreadyCreated();
        }
        isDisabled = true;

        address vaultAddress = getDeploymentAddress(salt);
        if (targetAddress != vaultAddress) {
            revert VaultAddressMismatch();
        }

        VaultAdmin vaultAdmin = new VaultAdmin(IVault(vaultAddress), _v2Vault, _pauseWindowDuration, _bufferPeriodDuration);

        VaultExtension vaultExtension = new VaultExtension(IVault(vaultAddress), vaultAdmin);

        ProtocolFeeController feeController = new ProtocolFeeController(IVault(vaultAddress));

        address deployedAddress = _create(abi.encode(vaultExtension, feeController), salt);

        // This should always be the case, but we enforce the end state to match the expected outcome anyways.
        if (deployedAddress != targetAddress) {
            revert VaultAddressMismatch();
        }

        emit VaultCreated(vaultAddress);
    }

    /// @notice Gets deployment address for a given salt.
    function getDeploymentAddress(bytes32 salt) public view returns (address) {
        return CREATE3.getDeployed(salt);
    }

    function _create(bytes memory constructorArgs, bytes32 finalSalt) internal returns (address) {
        return CREATE3.deploy(finalSalt, abi.encodePacked(_creationCode, constructorArgs), 0);
    }

    function _canPerform(bytes32 actionId, address user) internal view virtual override returns (bool) {
        return _v2Vault.getAuthorizer().canPerform(actionId, user, address(this));
    }
}
